# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FightingStyleRules do
  let(:sheet) { instance_double(Sheet, metadata: metadata) }
  let(:equipment) do
    {
      equipped: {
        main_hand: { 'api_index' => 'longbow' },
        off_hand: nil,
        armor: { 'api_index' => 'leather' }
      }
    }
  end

  before do
    allow(EquipmentRules).to receive(:weapon_props).and_return(type: 'ranged', hands: 2)
    allow(EquipmentRules).to receive(:is_weapon?).and_return(false)
  end

  context 'when fighting_style is an Array (wizard JSON)' do
    let(:metadata) do
      {
        'class_choices' => {
          'per_level' => {
            '2' => { 'fighting_style' => ['fs-archery'] }
          }
        }
      }
    end

    it 'applies +2 ranged attack (does not use Array#to_s garbage)' do
      out = described_class.new(sheet, equipment: equipment).call
      expect(out[:weapon_mods][:main_hand][:attack]).to eq(2)
      expect(out[:active_styles]).to include('Arquearia')
    end
  end
end
