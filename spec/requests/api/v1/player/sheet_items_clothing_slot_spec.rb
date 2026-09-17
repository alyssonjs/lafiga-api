# frozen_string_literal: true

require 'rails_helper'

# ROUPA (16/09/2026). Pedido da mesa: o Sirius veste a Cota de Malha E uma roupa
# de frio. A roupa vestia-se no slot `armor` (o torso), e equipar uma pedia para
# tirar a outra. Agora a roupa tem casa própria, `clothing`.
RSpec.describe 'SheetItems — slot de ROUPA', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Clothing Slot Spec') }
  let!(:sheet) { create(:sheet, character: character) }

  def catalogo!(nome, kind, category: nil, props: {})
    Item.create!(name: nome, api_index: "spec-#{nome.parameterize}-#{SecureRandom.hex(3)}",
                 kind: kind, category: category, props: props)
  end

  def linha!(item)
    SheetItem.create!(sheet: sheet, item_name: item.name, item_index: item.api_index,
                      category: 'Equipamento', quantity: 1, source: 'test')
  end

  def inventario
    get "/api/v1/player/sheet_items?sheet_id=#{sheet.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body['sheet_items']
  end

  it 'armadura e roupa ficam vestidas AO MESMO TEMPO' do
    # A armadura entra vestida direto: o que este exemplo prova é que EQUIPAR A
    # ROUPA não derruba nada — a proficiência de armadura é outra pergunta.
    cota = linha!(catalogo!('Spec Cota', 'armor'))
    cota.update_columns(equipped: true, slot: 'armor')
    roupa = linha!(catalogo!('Spec Roupa de Frio', 'gear', category: 'clothes'))

    post "/api/v1/player/sheet_items/#{roupa.id}/equip", params: { slot: 'clothing' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(roupa.reload).to have_attributes(equipped: true, slot: 'clothing')
    expect(cota.reload).to have_attributes(equipped: true, slot: 'armor')
  end

  it 'roupa classificada (category clothes) sem slot gravado responde clothing — leitor tolerante' do
    item = catalogo!('Spec Roupas Finas', 'gear', category: 'clothes')
    linha!(item)

    expect(inventario.find { |r| r['index'] == item.api_index }['equip_slot']).to eq('clothing')
  end

  it 'o slot DECLARADO continua vencendo a categoria' do
    item = catalogo!('Spec Capa-roupa', 'gear', category: 'clothes', props: { 'equip_slot' => 'cloak' })
    linha!(item)

    expect(inventario.find { |r| r['index'] == item.api_index }['equip_slot']).to eq('cloak')
  end

  it 'gear sem a categoria de roupa não ganha slot' do
    item = catalogo!('Spec Corda', 'gear')
    linha!(item)

    expect(inventario.find { |r| r['index'] == item.api_index }['equip_slot']).to be_nil
  end
end
