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

  context '⚠️ o mesmo estilo gravado duas vezes, com nomes diferentes' do
    # Ficha real (14/09): "Defesa" no nível 1 e "fs-defense" no nível 2.
    let(:metadata) do
      {
        'class_choices' => {
          'per_level' => {
            '1' => { 'fighting_style' => ['Defesa'] },
            '2' => { 'fighting_style' => ['fs-defense'] }
          }
        }
      }
    end

    it 'a Defesa vale +1 de CA, uma vez só' do
      out = described_class.new(sheet, equipment: equipment).call
      expect(out[:ac_bonus]).to eq(1)
      expect(out[:active_styles]).to eq(['Defesa'])
    end
  end
end
