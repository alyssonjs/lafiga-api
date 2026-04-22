# frozen_string_literal: true

require 'rails_helper'

# P2.13 — Paridade entre `metadata['resources']` (legado) e
# `runtime_state.class_resources_used` (Fase C, fonte canonica).
#
# Antes desta migracao havia duas trilhas de USED no backend, com risco de
# drift silencioso entre paineis. Esta spec trava o contrato:
#
#   1. Quando apenas runtime_state esta preenchido -> summary usa esse valor.
#   2. Quando apenas metadata['resources'] esta preenchido (sheet legado) ->
#      summary usa o legado (compat).
#   3. Quando os dois estao preenchidos com valores diferentes -> runtime_state
#      ganha (single source of truth).
#   4. Backward-compat: sheets sem nenhum dos dois retornam used=0.
RSpec.describe CharacterSheetSummaryService, type: :service do
  let(:user) do
    User.create!(
      email: "rt_par_#{SecureRandom.hex(4)}@example.com",
      username: "rtp#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end
  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 }
  end

  def build_sheet(metadata: {})
    character = Character.create!(user: user, name: "RT #{SecureRandom.hex(2)}", background: 'Sage')
    sheet = Sheet.create!(
      character: character, race: race,
      str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 10,
      hp_max: 10, hp_current: 10, current_level: 5, metadata: metadata,
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 5)
    sheet
  end

  def call_summary(sheet)
    cmd = described_class.call(sheet_id: sheet.id, sync: false)
    (cmd.respond_to?(:result) ? cmd.result : cmd)
  end

  describe 'precedencia de fontes' do
    it '(1) runtime_state apenas: summary reflete class_resources_used' do
      sheet = build_sheet
      sheet.runtime!.update!(class_resources_used: { 'second_wind' => 1, 'action_surge' => 1 })
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind][:used]).to eq(1)
      expect(res[:action_surge][:used]).to eq(1)
    end

    it '(2) metadata[resources] apenas (legado): summary respeita o valor antigo' do
      sheet = build_sheet(metadata: {
        'resources' => {
          'second_wind' => { 'used' => 1 },
          'action_surge' => { 'used' => 1 },
        },
      })
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind][:used]).to eq(1)
      expect(res[:action_surge][:used]).to eq(1)
    end

    it '(3) ambos preenchidos com valores diferentes: runtime_state vence (SoT)' do
      sheet = build_sheet(metadata: {
        'resources' => {
          'second_wind' => { 'used' => 0 },
          'action_surge' => { 'used' => 1 },
        },
      })
      sheet.runtime!.update!(class_resources_used: { 'second_wind' => 1, 'action_surge' => 0 })
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind][:used]).to eq(1), 'runtime: 1 deve vencer legado: 0'
      expect(res[:action_surge][:used]).to eq(0), 'runtime: 0 deve vencer legado: 1'
    end

    it '(4) sem fontes: used = 0 (no-op default)' do
      sheet = build_sheet
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind][:used]).to eq(0)
      expect(res[:action_surge][:used]).to eq(0)
    end

    it 'paridade pos-decremento via DecrementResourceService eh refletida no summary' do
      sheet = build_sheet
      Sheets::Runtime::DecrementResourceService.call(sheet, key: 'second_wind', delta: 1)
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind][:used]).to eq(1)
    end

    it 'parcialidade: chave so no runtime_state nao apaga chave so no legado' do
      sheet = build_sheet(metadata: {
        'resources' => { 'action_surge' => { 'used' => 1 } },
      })
      sheet.runtime!.update!(class_resources_used: { 'second_wind' => 1 })
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind][:used]).to eq(1), 'runtime preenchido'
      expect(res[:action_surge][:used]).to eq(1), 'legado preservado quando runtime nao tem a chave'
    end
  end
end
