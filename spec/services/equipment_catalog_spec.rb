require 'rails_helper'

RSpec.describe EquipmentCatalog do
  describe '.weapon_row' do
    it 'expõe a munição canônica da besta pesada' do
      row = described_class.weapon_row('heavy-crossbow')

      expect(row[:ammunition]).to eq(true)
      expect(row[:ammunition_index]).to eq('virote')
    end
  end
end
