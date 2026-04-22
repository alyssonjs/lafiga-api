# frozen_string_literal: true

require 'rails_helper'

# P1.15 — Backfill de build_resources com chaves que ja existiam em
# `class_resources.yml` (Fase C runtime) mas nao apareciam no payload do
# summary. Sem este fix, a UI nao recebia total/used para:
#   - Guerreiro: second_wind, indomitable
#   - Paladino: divine_sense, lay_on_hands
#   - Mago: arcane_recovery (+ max_slot_levels)
RSpec.describe CharacterSheetSummaryService, type: :service do
  let(:user) do
    User.create!(
      email: "resbf_#{SecureRandom.hex(4)}@example.com",
      username: "rb#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end

  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  def make_sheet(klass:, level:, abilities: { str: 10, dex: 14, con: 12, int: 10, wis: 10, cha: 14 }, metadata: {})
    character = Character.create!(user: user, name: "BF #{SecureRandom.hex(2)}", background: 'Sage')
    sheet = Sheet.create!(
      character: character,
      race: race,
      str: abilities[:str], dex: abilities[:dex], con: abilities[:con],
      int: abilities[:int], wis: abilities[:wis], cha: abilities[:cha],
      hp_max: 10, hp_current: 10, current_level: level,
      metadata: metadata,
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: level)
    sheet
  end

  def call_summary(sheet)
    cmd = described_class.call(sheet_id: sheet.id, sync: false)
    cmd.respond_to?(:result) ? cmd.result : cmd
  end

  describe 'Guerreiro (Fighter)' do
    let(:klass) do
      Klass.find_or_create_by!(api_index: 'fighter') do |k|
        k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
      end
    end

    it 'expoe second_wind { total: 1 } em qualquer nivel' do
      sheet = make_sheet(klass: klass, level: 1)
      res = call_summary(sheet)[:resources]
      expect(res[:second_wind]).to eq(total: 1, used: 0)
    end

    it 'NAO expoe indomitable abaixo do nivel 9' do
      sheet = make_sheet(klass: klass, level: 8)
      expect(call_summary(sheet)[:resources][:indomitable]).to be_nil
    end

    it 'expoe indomitable: 1 uso no nv 9, 2 no nv 13, 3 no nv 17' do
      [[9, 1], [12, 1], [13, 2], [16, 2], [17, 3], [20, 3]].each do |lvl, expected|
        sheet = make_sheet(klass: klass, level: lvl)
        res = call_summary(sheet)[:resources]
        expect(res[:indomitable]).to eq(total: expected, used: 0), "nv #{lvl} esperava #{expected}"
      end
    end

    it 'clampa used em total mesmo se metadata exagerar' do
      sheet = make_sheet(klass: klass, level: 1, metadata: { 'resources' => { 'second_wind' => { 'used' => 99 } } })
      expect(call_summary(sheet)[:resources][:second_wind][:used]).to eq(1)
    end
  end

  describe 'Paladino' do
    let(:klass) do
      Klass.find_or_create_by!(api_index: 'paladin') do |k|
        k.name = 'Paladino'; k.hit_die = 10; k.subclass_level = 3
      end
    end

    it 'expoe divine_sense baseado em CHA mod (min 1) e lay_on_hands = level * 5' do
      sheet = make_sheet(klass: klass, level: 5, abilities: { str: 16, dex: 10, con: 14, int: 8, wis: 12, cha: 18 })
      res = call_summary(sheet)[:resources]
      expect(res[:divine_sense]).to eq(total: 5, used: 0) # 1 + CHA(+4) = 5
      expect(res[:lay_on_hands]).to eq(total: 25, used: 0) # 5 * 5
    end

    it 'divine_sense minimo de 1 mesmo com CHA 8 (mod -1)' do
      sheet = make_sheet(klass: klass, level: 1, abilities: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 8 })
      res = call_summary(sheet)[:resources]
      expect(res[:divine_sense][:total]).to eq(1)
    end

    it 'continua emitindo channel_divinity (nao-regressao do P1.1)' do
      sheet = make_sheet(klass: klass, level: 5)
      expect(call_summary(sheet)[:resources][:channel_divinity]).to be_present
    end
  end

  describe 'Mago (Wizard)' do
    let(:klass) do
      Klass.find_or_create_by!(api_index: 'wizard') do |k|
        k.name = 'Mago'; k.hit_die = 6; k.subclass_level = 2
      end
    end

    it 'expoe arcane_recovery: { total: 1, max_slot_levels: ceil(level/2) }' do
      [[1, 1], [2, 1], [3, 2], [4, 2], [9, 5], [20, 10]].each do |lvl, expected|
        sheet = make_sheet(klass: klass, level: lvl)
        res = call_summary(sheet)[:resources]
        expect(res[:arcane_recovery]).to be_present, "nv #{lvl} esperava arcane_recovery"
        expect(res[:arcane_recovery][:total]).to eq(1)
        expect(res[:arcane_recovery][:max_slot_levels]).to eq(expected), "nv #{lvl}"
      end
    end
  end
end
