# frozen_string_literal: true

# COSTAS (`back`): aljava e bolsa fundiram-se numa casa só (30/08).
#
# São o mesmo lugar do corpo, e leva uma coisa de cada vez. A escolha não
# aperta o arqueiro porque o CINTO tem slot livre que aceita aljava — mochila
# nas costas e aljava na cintura continua possível.
#
# ⚠️ O `canonicalize_slot` é a porta ÚNICA da tradução: os dois controllers
# validam o param ANTES do modelo, e uma cópia por porta é como a próxima fusão
# de slot quebra só metade delas.
require 'rails_helper'

RSpec.describe SheetItem, 'slot das costas' do
  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }

  def linha!(nome, slot: nil, index: nil)
    described_class.create!(sheet: sheet, item_name: nome, item_index: index,
                            category: 'Itens Gerais', quantity: 1, source: 'test',
                            equipped: slot.present?, slot: slot)
  end

  describe 'canonicalize_slot' do
    it 'traduz os dois slots legados para `back`' do
      expect(described_class.canonicalize_slot('quiver')).to eq('back')
      expect(described_class.canonicalize_slot('bag')).to eq('back')
    end

    it 'mantem a traducao antiga do diadema' do
      expect(described_class.canonicalize_slot('circlet')).to eq('helmet')
    end

    it 'deixa passar o que ja e canonico' do
      expect(described_class.canonicalize_slot('back')).to eq('back')
      expect(described_class.canonicalize_slot('main_hand')).to eq('main_hand')
    end
  end

  it 'os slots legados NAO estao mais em ALL_SLOTS' do
    expect(described_class::ALL_SLOTS).to include('back')
    expect(described_class::ALL_SLOTS).not_to include('quiver')
    expect(described_class::ALL_SLOTS).not_to include('bag')
  end

  it 'gravar com o slot legado canonicaliza sozinho' do
    linha = linha!('Aljava', slot: 'quiver')

    expect(linha.reload.slot).to eq('back')
  end

  describe 'worn_bag_for' do
    before do
      Item.create!(api_index: 'mochila-b', name: 'Mochila', kind: 'gear', category: 'bag',
                   props: { 'capacity_kg' => 15 })
    end

    it 'acha a BOLSA quando e ela que esta nas costas' do
      mochila = linha!('Mochila', slot: 'back', index: 'mochila-b')

      expect(described_class.worn_bag_for(sheet)).to eq(mochila)
    end

    it 'devolve nil quando quem esta nas costas e a ALJAVA' do
      linha!('Aljava', slot: 'back')

      # O slot é um só; quem decide é a natureza do item.
      expect(described_class.worn_bag_for(sheet)).to be_nil
    end

    it 'devolve nil com a bolsa guardada mas NAO vestida' do
      linha!('Mochila', index: 'mochila-b')

      expect(described_class.worn_bag_for(sheet)).to be_nil
    end
  end

  it 'aljava e bolsa DISPUTAM a casa — e o que a fusao significa' do
    Item.create!(api_index: 'mochila-x', name: 'Mochila', kind: 'gear', category: 'bag',
                 props: { 'capacity_kg' => 15 })
    aljava = linha!('Aljava', slot: 'back')
    linha!('Mochila', slot: 'back', index: 'mochila-x')

    # A exclusividade de slot já existia para o corpo todo; as costas herdam-na.
    expect(aljava.reload.equipped).to be(false)
  end
end
