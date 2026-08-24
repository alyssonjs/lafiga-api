# frozen_string_literal: true

require 'rails_helper'

# Peso do item na CARROCA.
#
# A instancia (`props_json['weight_lb']`) manda quando existe; sem ela, o peso
# vem do CATALOGO (kg x 2, convencao do livro). Antes do fallback, item
# guardado sem a prop pesava 0 na carroca — carga de graca.
RSpec.describe GroupCarts do
  let(:user)      { create(:user) }
  let(:race)      { create(:race) }
  let(:sub_race)  { create(:sub_race, race: race) }
  let(:character) { create(:character, user: user, name: 'Cart Weight PC') }
  let!(:sheet)    { create(:sheet, character: character, race: race, sub_race: sub_race) }

  let!(:base) do
    Item.create!(name: 'Spec Barril', api_index: "spec-barril-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'gear', weight_kg: 2.5)
  end

  it 'usa o weight_lb da instancia quando gravado' do
    si = SheetItem.create!(sheet: sheet, item_name: 'Spec Barril', item_index: base.api_index,
                           category: 'gear', quantity: 1, source: 'test',
                           props_json: { 'weight_lb' => 7 })
    expect(described_class.item_weight_lb(si)).to eq(7.0)
  end

  it 'sem a prop, cai no catalogo: 2,5 kg viram 5 lb' do
    si = SheetItem.create!(sheet: sheet, item_name: 'Spec Barril', item_index: base.api_index,
                           category: 'gear', quantity: 1, source: 'test')
    expect(described_class.item_weight_lb(si)).to eq(5.0)
  end

  it 'item sem catalogo e sem prop pesa 0 (nao explode)' do
    si = SheetItem.create!(sheet: sheet, item_name: 'Coisa Inventada Xyz', item_index: 'coisa-inventada-xyz',
                           category: 'gear', quantity: 1, source: 'test')
    expect(described_class.item_weight_lb(si)).to eq(0.0)
  end
end
