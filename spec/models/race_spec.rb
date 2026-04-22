# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Race, type: :model do
  describe '#base_traits vs #traits' do
    it 'returns only race-wide traits for base_traits, not other subraces' do
      race = create(:race)
      sub_a = create(:sub_race, race: race, name: 'Sub A')
      sub_b = create(:sub_race, race: race, name: 'Sub B')

      t_base = Trait.create!(api_index: 'spec-base-trait', name: 'Base Trait', description: 'all')
      t_a = Trait.create!(api_index: 'spec-sub-a-trait', name: 'Sub A Only', description: 'a')
      t_b = Trait.create!(api_index: 'spec-sub-b-trait', name: 'Sub B Only', description: 'b')

      RaceTrait.create!(race: race, trait: t_base, sub_race: nil)
      RaceTrait.create!(race: race, trait: t_a, sub_race: sub_a)
      RaceTrait.create!(race: race, trait: t_b, sub_race: sub_b)

      race.reload

      expect(race.traits.pluck(:id).sort).to eq([t_base.id, t_a.id, t_b.id].sort)
      expect(race.base_traits.pluck(:id)).to eq([t_base.id])
      expect(sub_a.traits.pluck(:id)).to eq([t_a.id])
    end
  end
end
