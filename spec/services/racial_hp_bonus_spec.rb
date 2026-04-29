# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RacialHpBonus do
  before { RaceRules.reload! }

  describe '.per_level_from_applied' do
    it 'retorna 1 quando traits incluem dwarven_toughness' do
      traits = [{ key: 'dwarven_toughness' }]
      expect(described_class.per_level_from_applied(traits)).to eq(1)
    end

    it 'retorna 0 sem traço com grant hp_per_level' do
      expect(described_class.per_level_from_applied([{ key: 'keen_senses' }])).to eq(0)
    end
  end

  describe '.per_level_for_sheet com api_index hill_dwarf (SRD vs YAML hill)' do
    let(:race) { Race.find_or_create_by!(api_index: 'dwarf') { |r| r.name = 'Anão' } }
    let!(:hill_srd) do
      SubRace.find_or_create_by!(race_id: race.id, api_index: 'hill_dwarf') do |s|
        s.name = 'Anão da Colina'
      end
    end

    it 'resolve alias e soma hp_per_level da Robustez Anã' do
      sheet = Sheet.new(race: race, sub_race: hill_srd, metadata: { 'race_choices' => {} })
      expect(described_class.per_level_for_sheet(sheet)).to eq(1)
    end

    it 'resolve pelo nome PT quando api_index da sub-raça é nil (slug anao_da_colina)' do
      hill_pt = SubRace.create!(race_id: race.id, api_index: nil, name: 'Anão da Colina')
      sheet = Sheet.new(race: race, sub_race: hill_pt, metadata: { 'race_choices' => {} })
      expect(described_class.per_level_for_sheet(sheet)).to eq(1)
    end
  end
end
