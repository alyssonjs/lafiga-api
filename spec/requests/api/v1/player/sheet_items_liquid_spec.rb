# frozen_string_literal: true

require 'rails_helper'

# Barril pela ficha — o contrato HTTP de `transfer_liquid` (14/09/2026).
RSpec.describe 'Ficha — recipiente de líquido', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  before do
    Item.find_or_initialize_by(api_index: 'barril')
        .update!(name: 'Barril', kind: 'gear', category: 'container', weight_kg: 35,
                 props: { 'liquid_capacity_l' => 160 })
  end

  let(:barril) do
    SheetItem.create!(sheet: sheet, item_name: 'Barril', item_index: 'barril',
                      category: 'Itens Gerais', quantity: 1, source: 'test')
  end

  def mover(item, corpo, cabecalhos = headers)
    post "/api/v1/player/sheet_items/#{item.id}/transfer_liquid", params: corpo, headers: cabecalhos, as: :json
    response
  end

  it 'guardar devolve a linha com o conteúdo, o teto e o peso junto' do
    mover(barril, amount_l: 120, name: 'Água')

    expect(response).to have_http_status(:ok), -> { response.body }
    linha = response.parsed_body['sheet_item']
    expect(linha['props']['liquid']).to eq('name' => 'Água', 'amount_l' => 120.0)
    expect(linha['liquid_capacity_l']).to eq(160.0)
    expect(linha['weight_lb']).to eq(((35 + 120) * EquipmentRules::LB_PER_KG).to_f)
  end

  it '⚠️ o que não cabe volta 422 com o motivo' do
    mover(barril, amount_l: 170)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('Barril comporta até 160 L (ficaria com 170)')
  end

  it 'a ficha de OUTRO jogador é proibida' do
    mover(barril, { amount_l: 10 }, bearer_headers_for(create(:user)))

    expect(response).to have_http_status(:forbidden)
    expect(barril.reload.liquid_contents).to be_nil
  end
end
