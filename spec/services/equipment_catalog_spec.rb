require 'rails_helper'

RSpec.describe EquipmentCatalog do
  describe '.weapon_row' do
    # 05/10 (a mesa: "cada tipo de besta tem seu tipo específico de virote" e "o mesmo também deve servir para arcos"):
    # cada arma de disparo puxa a munição dela (`config/equipment.yml`, chave `ammunition_index`).
    it 'expõe a munição canônica de cada besta e de cada arco' do
      row = described_class.weapon_row('heavy-crossbow')

      expect(row[:ammunition]).to eq(true)
      expect(row[:ammunition_index]).to eq('virote-de-besta-pesada')
      expect(described_class.weapon_row('hand-crossbow')[:ammunition_index]).to eq('virote-de-besta-de-mao')
      expect(described_class.weapon_row('besta-leve')[:ammunition_index]).to eq('virote')
      expect(described_class.weapon_row('longbow')[:ammunition_index]).to eq('flecha-de-arco-longo')
      expect(described_class.weapon_row('arco-curto')[:ammunition_index]).to eq('flecha')
    end
  end
end
