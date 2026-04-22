# frozen_string_literal: true

require 'rails_helper'

# Bug #2 Adimael Neverdie: a aba "Efeitos de Itens Equipados" exibia +10 ft de
# deslocamento que vinha do feat Mobilidade (e nao de equipamento). Este spec
# trava o contrato:
#   - `summary[:modifiers][:speed_bonus]` = TOTAL (todas as origens)
#   - `summary[:modifiers][:equipment_speed_bonus]` = SO :item
#   - `summary[:modifiers][:feat_speed_bonus]` = SO :feat
# A UI deve consumir os campos por origem para nao desinformar o jogador.
RSpec.describe CharacterSheetSummaryService, type: :service do
  let(:user) do
    User.create!(
      email: "speed_breakdown_#{SecureRandom.hex(4)}@example.com",
      username: "spd#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end
  let(:race) { Race.find_or_create_by!(api_index: 'elf') { |r| r.name = 'Elfo' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'wood') { |s| s.name = 'Elfo da Floresta' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end

  let(:character) { Character.create!(user: user, name: "Spd #{SecureRandom.hex(2)}", background: 'Sage') }

  def build_sheet(metadata: {})
    sheet = Sheet.create!(
      character: character,
      race: race, sub_race: sub_race,
      str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 10,
      hp_max: 10, hp_current: 10, current_level: 4,
      metadata: metadata,
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 4)
    sheet
  end

  context 'quando o personagem so tem o feat Mobilidade (sem item magico de speed)' do
    let(:sheet) do
      build_sheet(
        metadata: {
          'feats' => [{ 'feat_id' => 'mobilidade' }],
        },
      )
    end

    it 'isola corretamente speed_bonus por origem', :aggregate_failures do
      cmd = described_class.call(sheet_id: sheet.id, sync: false)
      summary = cmd.respond_to?(:result) ? cmd.result : cmd
      mods = summary[:modifiers] || {}

      expect(mods[:speed_bonus]).to eq(10), 'total de speed bonus (feat + item)'
      expect(mods[:feat_speed_bonus]).to eq(10), 'somente feats — Mobilidade'
      expect(mods[:equipment_speed_bonus]).to eq(0),
        "esperado 0 (nenhum item magico de speed equipado), veio #{mods[:equipment_speed_bonus].inspect}.\n" \
        '  Bug Adimael: aba "Efeitos de Itens Equipados" mostrava +10 ft que vinha do feat.'
    end
  end
end
