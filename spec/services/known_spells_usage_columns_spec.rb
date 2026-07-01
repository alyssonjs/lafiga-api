# frozen_string_literal: true

require 'rails_helper'

# D6 — KnownSpellsAggregator propaga uses_per_rest/uses_remaining das magias
# raciais 1/LDesc para as linhas de known_by_level (antes vinham null no summary).
RSpec.describe 'D6 — KnownSpellsAggregator usage columns', type: :service do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user) }
  let(:race) { Race.find_by(api_index: 'tiefling') || create(:race, name: 'Tiefling', api_index: 'tiefling') }
  let(:klass) do
    Klass.find_by(api_index: 'barbarian') || create(:klass, name: 'Bárbaro', api_index: 'barbarian', hit_die: 12)
  end
  let(:sheet) { create(:sheet, character: character, race: race, str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 14) }
  let(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: klass, level: 5) }

  let!(:hellish) { create(:spell, name: 'Repreensão Infernal D6', level: 1) }
  let!(:cantrip) { create(:spell, name: 'Taumaturgia D6', level: 0) }

  before { sheet_klass }

  def rows
    KnownSpellsAggregator.new(sheet).call[:known_by_level].values.flatten
  end

  it 'magia racial 1/LDesc carrega uses_per_rest=LR e uses_remaining' do
    SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: hellish, source: 'race',
                            uses_per_rest: 'LR', uses_remaining: 1, gained_at_class_level: 3)
    row = rows.find { |r| r[:id] == hellish.id }
    expect(row[:uses_per_rest]).to eq('LR')
    expect(row[:uses_remaining]).to eq(1)
    expect(row[:known_source]).to eq('race')
  end

  it 'truque racial à vontade NÃO ganha uses_per_rest (nil)' do
    SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: cantrip, source: 'race',
                            uses_per_rest: nil, uses_remaining: 0)
    row = rows.find { |r| r[:id] == cantrip.id }
    expect(row).not_to have_key(:uses_per_rest)
  end
end
