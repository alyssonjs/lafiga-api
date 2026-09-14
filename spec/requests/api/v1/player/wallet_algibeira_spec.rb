# frozen_string_literal: true

require 'rails_helper'

# ALGIBEIRA como a aljava das MOEDAS — o contrato HTTP.
#
# `coin_transfer` ganhou pontas de ITEM (`from_sheet_item_id`/`to_sheet_item_id`)
# ao lado das de algibeira: o jogador guarda moedas numa Algibeira do inventário
# sem precisar de a criar antes. Teto e posse do item são do SERVIDOR.
RSpec.describe 'Carteira — Algibeira do inventário guarda moedas', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) do
    s = create(:sheet, character: character)
    s.update!(coins: { 'cp' => 0, 'sp' => 0, 'ep' => 0, 'gp' => 400, 'pp' => 0 })
    s
  end

  before do
    Item.find_or_initialize_by(api_index: 'algibeira')
        .update!(name: 'Algibeira', kind: 'gear', props: { 'coin_capacity' => 300 })
  end

  def algibeira!(ficha = sheet)
    SheetItem.create!(sheet: ficha, item_name: 'Algibeira', item_index: 'algibeira',
                      category: 'Itens Gerais', quantity: 1, source: 'test')
  end

  # Posicionais, não keywords: `mover(from_pouch_id: …)` chega como o Hash do payload.
  def mover(payload, rota = "/api/v1/player/sheets/#{sheet.id}/wallet", cabecalhos = headers)
    put rota, params: { coin_transfer: payload }, headers: cabecalhos, as: :json
    response
  end

  def algibeira_do(item)
    response.parsed_body['coin_pouches'].find { |p| p['sheet_item_id'] == item.id }
  end

  it 'guardar numa Algibeira cria a algibeira DELA e o total da ficha não muda' do
    item = algibeira!

    mover(from_pouch_id: 'primary', to_sheet_item_id: item.id, wallet: { gp: 120 })

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(algibeira_do(item)).to include('gp' => 120, 'name' => 'Algibeira')
    expect(response.parsed_body['coin_pouches'].find { |p| p['id'] == 'primary' }['gp']).to eq(280)
    expect(response.parsed_body['wallet']['gp']).to eq(400)
  end

  it 'tirar da Algibeira devolve para a Carteira' do
    item = algibeira!
    mover(from_pouch_id: 'primary', to_sheet_item_id: item.id, wallet: { gp: 120 })

    mover(from_sheet_item_id: item.id, to_pouch_id: 'primary', wallet: { gp: 20 })

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(algibeira_do(item)['gp']).to eq(100)
  end

  it '⚠️ o TETO é do servidor: 301 moedas numa algibeira de 300 → 422, e nada fica criado' do
    item = algibeira!

    mover(from_pouch_id: 'primary', to_sheet_item_id: item.id, wallet: { gp: 301 })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/comporta até 300 moedas/)
    expect(sheet.reload.coin_pouches.size).to eq(1)
    expect(sheet.wallet_hash['gp']).to eq(400)
  end

  it '⚠️ item de OUTRA ficha não serve de algibeira — 404' do
    item_alheio = algibeira!(create(:sheet))

    mover(from_pouch_id: 'primary', to_sheet_item_id: item_alheio.id, wallet: { gp: 10 })

    expect(response).to have_http_status(:not_found)
    expect(sheet.reload.coin_pouches.size).to eq(1)
  end

  it '⚠️ nome parecido sem declaração no catálogo NÃO guarda ("bolsa PO" é dinheiro solto)' do
    item = SheetItem.create!(sheet: sheet, item_name: 'bolsa PO', category: 'Itens Gerais',
                             quantity: 120, source: 'test')

    mover(from_pouch_id: 'primary', to_sheet_item_id: item.id, wallet: { gp: 10 })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/não guarda moedas/)
  end

  it 'o Mestre move pela rota de admin com o mesmo contrato' do
    dm_role = Role.find_by(name: 'DM') || create(:role, name: 'DM')
    dm = create(:user, role: dm_role)
    item = algibeira!

    mover({ from_pouch_id: 'primary', to_sheet_item_id: item.id, wallet: { gp: 5 } },
          "/api/v1/admin/sheets/#{sheet.id}/wallet", bearer_headers_for(dm))

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(algibeira_do(item)['gp']).to eq(5)
  end

  it 'apagar a Algibeira pela bolsa devolve as moedas para a Carteira' do
    item = algibeira!
    mover(from_pouch_id: 'primary', to_sheet_item_id: item.id, wallet: { gp: 120 })

    delete "/api/v1/player/sheet_items/#{item.id}", headers: headers

    expect(response).to have_http_status(:no_content)
    sheet.reload
    expect(sheet.coin_pouches.size).to eq(1)
    expect(sheet.coin_pouches.first['gp']).to eq(400)
  end

  it 'a linha da Algibeira informa a capacidade — e duas NÃO empilham' do
    corpo = { sheet_id: sheet.id, item_index: 'algibeira', item_name: 'Algibeira', category: 'Itens Gerais',
              quantity: 1, source: 'manual', props_json: { weight_lb: 1 } }
    2.times { post '/api/v1/player/sheet_items', params: { sheet_item: corpo }, headers: headers, as: :json }

    expect(response.parsed_body.dig('sheet_item', 'coin_capacity')).to eq(300), -> { response.body }
    expect(SheetItem.where(sheet_id: sheet.id, item_index: 'algibeira').pluck(:quantity)).to eq([1, 1])
  end
end
