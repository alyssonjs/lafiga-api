# frozen_string_literal: true

require 'rails_helper'

# `sheet_items.props_json` e estado da INSTANCIA — nao carrega o `mount_slot`
# que o CATALOGO carimba. Sem expor isto, uma sela na mochila do jogador nao
# aparecia no seletor de equipamento da montaria.
RSpec.describe 'SheetItem#as_inventory_json mount_props', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Mount Props Spec') }
  let!(:sheet) { create(:sheet, character: character) }

  let!(:sela) do
    Item.create!(name: 'Spec Sela militar', api_index: "spec-sela-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'tack', props: { 'mount_slot' => 'saddle' })
  end
  let!(:alforje) do
    Item.create!(name: 'Spec Alforje', api_index: "spec-alforje-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'tack', props: { 'mount_slot' => 'bags', 'capacity_lb' => 30 })
  end
  let!(:corda) do
    Item.create!(name: 'Spec Corda', api_index: "spec-corda-#{SecureRandom.hex(3)}", kind: 'gear')
  end

  def bag!(item)
    SheetItem.create!(sheet: sheet, item_name: item.name, item_index: item.api_index,
                      category: 'Equipamento', quantity: 1, source: 'test')
  end

  def inventario
    get "/api/v1/player/sheet_items?sheet_id=#{sheet.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body['sheet_items']
  end

  it 'a sela leva o slot da montaria' do
    bag!(sela)

    linha = inventario.find { |r| r['index'] == sela.api_index }
    expect(linha.dig('mount_props', 'mount_slot')).to eq('saddle')
  end

  it 'o alforje leva a capacidade junto' do
    bag!(alforje)

    linha = inventario.find { |r| r['index'] == alforje.api_index }
    expect(linha['mount_props']).to include('mount_slot' => 'bags', 'capacity_lb' => 30)
  end

  it 'REGRESSAO: item comum nao ganha mount_props' do
    bag!(corda)

    linha = inventario.find { |r| r['index'] == corda.api_index }
    expect(linha['mount_props']).to be_nil
  end
end
