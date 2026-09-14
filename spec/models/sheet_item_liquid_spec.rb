# frozen_string_literal: true

require 'rails_helper'

# RECIPIENTE DE LÍQUIDO — o Barril guarda água (14/09/2026).
#
# O conteúdo vive na LINHA da ficha (cada barril tem o seu) e pesa junto, 1 kg
# por litro — decisão do mestre. Teto, saldo e "um líquido por recipiente" são
# do servidor.
RSpec.describe SheetItem, 'recipiente de líquido' do
  let(:sheet) { create(:sheet) }

  before do
    Item.find_or_initialize_by(api_index: 'barril')
        .update!(name: 'Barril', kind: 'gear', category: 'container', weight_kg: 35,
                 props: { 'liquid_capacity_l' => 160 })
  end

  def barril!
    SheetItem.create!(sheet: sheet, item_name: 'Barril', item_index: 'barril',
                      category: 'Itens Gerais', quantity: 1, source: 'test')
  end

  it 'o Barril do catálogo leva 160 litros' do
    b = barril!
    expect(b.liquid_capacity_l).to eq(160.0)
    expect(b.liquid_container?).to be true
    expect(b.as_inventory_json[:liquid_capacity_l]).to eq(160.0)
  end

  it 'guardar sem nome enche de Água; tirar devolve; esvaziar limpa a linha' do
    b = barril!
    b.transfer_liquid!(120)
    expect(b.reload.props_json['liquid']).to eq('name' => 'Água', 'amount_l' => 120.0)

    b.transfer_liquid!(-20)
    expect(b.reload.props_json['liquid']['amount_l']).to eq(100.0)

    b.transfer_liquid!(-100)
    expect(b.reload.props_json).not_to have_key('liquid')
  end

  it 'aceita frações e o nome do líquido' do
    b = barril!
    b.transfer_liquid!(0.5, name: 'Vinho')
    expect(b.reload.liquid_contents).to eq('name' => 'Vinho', 'amount_l' => 0.5)
  end

  it '⚠️ não passa do teto — e diz quanto ficaria' do
    b = barril!
    b.transfer_liquid!(150)
    expect { b.transfer_liquid!(20) }
      .to raise_error(ArgumentError, 'Barril comporta até 160 L (ficaria com 170)')
    expect(b.reload.liquid_contents['amount_l']).to eq(150.0)
  end

  it 'não tira mais do que tem' do
    b = barril!
    b.transfer_liquid!(10)
    expect { b.transfer_liquid!(-11) }.to raise_error(ArgumentError, 'Barril só tem 10 L')
  end

  it '⚠️ um líquido por recipiente: Vinho num barril com Água é recusado' do
    b = barril!
    b.transfer_liquid!(50, name: 'Água')
    expect { b.transfer_liquid!(10, name: 'Vinho') }
      .to raise_error(ArgumentError, 'Barril tem Água: esvazie antes de guardar Vinho')
    # O mesmo líquido escrito com outra caixa é o mesmo líquido.
    expect { b.transfer_liquid!(10, name: 'água') }.not_to raise_error
    expect(b.reload.liquid_contents).to eq('name' => 'Água', 'amount_l' => 60.0)
  end

  it 'item que não guarda líquido recusa' do
    corda = SheetItem.create!(sheet: sheet, item_name: 'Corda', category: 'Itens Gerais', quantity: 1, source: 'test')
    expect { corda.transfer_liquid!(1) }.to raise_error(ArgumentError, 'Corda não guarda líquido')
  end

  describe 'peso (1 kg por litro)' do
    it '⚠️ o conteúdo pesa junto no peso da linha' do
      b = barril!
      vazio = EquipmentRules.item_weight_kg(b)
      b.transfer_liquid!(120)
      b.reload

      expect(EquipmentRules.item_weight_kg(b)).to eq(vazio + 120.0)
      expect(b.as_inventory_json[:weight_lb]).to eq(((vazio + 120.0) * EquipmentRules::LB_PER_KG).round(2))
    end

    it 'e no total carregado da ficha' do
      b = barril!
      antes = EquipmentProfileService.new(sheet).call[:carry][:total_kg]
      b.transfer_liquid!(40)

      expect(EquipmentProfileService.new(sheet.reload).call[:carry][:total_kg]).to eq((antes + 40.0).round(2))
    end

    it 'o item do catálogo não ganha peso de conteúdo' do
      expect(EquipmentRules.liquid_weight_kg(Item.find_by(api_index: 'barril'))).to eq(0.0)
    end
  end

  it 'cada barril é uma linha: recipiente de líquido não empilha' do
    expect(SheetItem.container_instance?(barril!)).to be true
  end
end
