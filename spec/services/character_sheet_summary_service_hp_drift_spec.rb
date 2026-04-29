# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterSheetSummaryService, 'HP drift (metadata vs colunas)' do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:dwarf) { Race.find_or_create_by!(api_index: 'dwarf') { |r| r.name = 'Anão' } }
  let!(:hill) { SubRace.find_or_create_by!(race_id: dwarf.id, api_index: 'hill') { |s| s.name = 'Anão da Colina' } }
  let(:cleric) { create(:klass, hit_die: 8, api_index: "sumhp_#{SecureRandom.hex(4)}") }

  before { RaceRules.reload! }

  it 'com sync: true, sobe hp_max/hp_current quando per_level + racial > colunas' do
    per = {
      '1' => { 'hp' => { 'method' => 'max', 'dieResult' => 8, 'conMod' => 2, 'total' => 10 } },
    }
    (2..7).each do |lv|
      per[lv.to_s] = { 'hp' => { 'method' => 'average', 'dieResult' => 5, 'conMod' => 2, 'total' => 7 } }
    end

    sheet = create(:sheet, character: character, race: dwarf, sub_race: hill,
                          con: 14, hp_max: 52, hp_current: 52, current_level: 7,
                          metadata: { 'class_choices' => { 'per_level' => per } })
    create(:sheet_klass, sheet: sheet, klass: cleric, level: 7)

    result = described_class.call(sheet_id: sheet.id, sync: true)
    expect(result).to be_success

    sheet.reload
    expect(sheet.hp_max).to eq(59)
    expect(sheet.hp_current).to eq(59)

    hp = result.result[:sheet][:hp_max]
    expect(hp).to eq(59)
  end

  it 'com sync: false, não altera colunas (apenas não sobe erro)' do
    per = { '1' => { 'hp' => { 'total' => 10 } } }
    sheet = create(:sheet, character: character, race: dwarf, sub_race: hill,
                          con: 14, hp_max: 52, hp_current: 52, current_level: 7,
                          metadata: { 'class_choices' => { 'per_level' => per } })
    create(:sheet_klass, sheet: sheet, klass: cleric, level: 7)

    described_class.call(sheet_id: sheet.id, sync: false)
    sheet.reload
    expect(sheet.hp_max).to eq(52)
  end
end
