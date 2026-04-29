# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterSheetEdits::ReviewEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:dwarf_race) { Race.find_or_create_by!(api_index: 'dwarf') { |r| r.name = 'Anão' } }
  let!(:hill_sub) do
    SubRace.find_or_create_by!(race_id: dwarf_race.id, api_index: 'hill_dwarf') do |s|
      s.name = 'Anão da Colina'
    end
  end
  let(:klass) { create(:klass, hit_die: 8, api_index: "review_hp_#{SecureRandom.hex(4)}") }

  before { RaceRules.reload! }

  it 'sincroniza hp_max a partir de per_level + racial ao gravar revisão' do
    per = {
      '1' => { 'hp' => { 'method' => 'max', 'dieResult' => 8, 'conMod' => 2, 'total' => 10 } },
    }
    (2..7).each do |lv|
      per[lv.to_s] = { 'hp' => { 'method' => 'average', 'dieResult' => 5, 'conMod' => 2, 'total' => 7 } }
    end
    sheet = create(:sheet, character: character, race: dwarf_race, sub_race: hill_sub,
                          con: 14, hp_max: 53, hp_current: 53, current_level: 7,
                          metadata: { 'class_choices' => { 'per_level' => per } })
    create(:sheet_klass, sheet: sheet, klass: klass, level: 7)

    described_class.new(character: character.reload, data: {}).call
    sheet.reload

    # 10 + 6×7 (média+CON em 2–7) + 7×1 (Robustez Anã) = 59
    expect(sheet.hp_max).to eq(59)
    expect(sheet.hp_current).to eq(59)
  end
end
