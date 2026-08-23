# frozen_string_literal: true

require 'rails_helper'

# Depósito móvel do GRUPO. O item nunca muda de dono — fica na ficha de quem
# comprou e só aponta para a carroça. É isso que dá "de quem é cada item" sem
# transferência: o `sheet_id` sempre foi a resposta.
#
# Autorização por PERTENCER AO GRUPO, não por posse: a carroça é compartilhada.
RSpec.describe 'Api::V1::Player::GroupCartsController', type: :request do
  let(:dono)   { create(:user) }
  let(:colega) { create(:user) }
  let(:estranho) { create(:user) }
  let(:group) { create(:group, name: 'Carroça Spec') }

  let!(:pc_dono)   { create(:character, user: dono, group: group, name: 'Dono') }
  let!(:pc_colega) { create(:character, user: colega, group: group, name: 'Colega') }
  let!(:sheet_dono)   { create(:sheet, character: pc_dono) }
  let!(:sheet_colega) { create(:sheet, character: pc_colega) }

  let(:h_dono)   { bearer_headers_for(dono) }
  let(:h_colega) { bearer_headers_for(colega) }
  let(:h_estranho) { bearer_headers_for(estranho) }

  def criar_carroca!(headers = h_dono, mounts: [])
    post "/api/v1/player/groups/#{group.id}/carts",
         params: { cart: { id: 'cart-1', name: 'Carroça', weight_lb: 220, mounts: mounts } },
         headers: headers, as: :json
  end

  def item!(sheet, nome: 'Barril', qtd: 1, peso: 10)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: nome.parameterize,
                      category: 'Equipamento', quantity: qtd, source: 'test',
                      props_json: { 'weight_lb' => peso })
  end

  def guardar(item, headers, quantity: nil, remove: false)
    post "/api/v1/player/groups/#{group.id}/carts/cart-1/stow",
         params: { sheet_item_id: item.id, quantity: quantity, remove: remove },
         headers: headers, as: :json
  end

  def prop(si) = (si.reload.props_json || {})[GroupCarts::CONTAINER_PROP]

  it 'membro do grupo cria a carroça' do
    criar_carroca!

    expect(response).to have_http_status(:created)
    expect(group.reload.carts.first['name']).to eq('Carroça')
  end

  it 'REGRESSAO: quem nao e do grupo nao ve nem cria' do
    criar_carroca!(h_estranho)
    expect(response).to have_http_status(:not_found)

    get "/api/v1/player/groups/#{group.id}/carts", headers: h_estranho, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'o item guardado CONTINUA na ficha do dono' do
    criar_carroca!
    it_dono = item!(sheet_dono)

    guardar(it_dono, h_dono)

    expect(response).to have_http_status(:ok)
    expect(prop(it_dono)).to eq('cart-1')
    expect(it_dono.reload.sheet_id).to eq(sheet_dono.id)
  end

  it 'REGRESSAO: QUALQUER um do grupo tira o item de outro' do
    criar_carroca!
    it_dono = item!(sheet_dono)
    guardar(it_dono, h_dono)

    # o colega tira — e o item volta para a bolsa do DONO, nao para a dele
    guardar(it_dono, h_colega, remove: true)

    expect(response).to have_http_status(:ok)
    expect(prop(it_dono)).to be_nil
    expect(it_dono.reload.sheet_id).to eq(sheet_dono.id)
  end

  it 'a listagem mostra itens de TODAS as fichas, com o dono de cada um' do
    criar_carroca!
    guardar(item!(sheet_dono, nome: 'Barril'), h_dono)
    guardar(item!(sheet_colega, nome: 'Tenda'), h_colega)

    get "/api/v1/player/groups/#{group.id}/carts/cart-1/items", headers: h_colega, as: :json

    expect(response).to have_http_status(:ok)
    linhas = response.parsed_body['items']
    expect(linhas.map { |l| l['name'] }).to match_array(%w[Barril Tenda])
    expect(linhas.map { |l| l['owner_name'] }).to match_array(%w[Dono Colega])
  end

  it 'capacidade: 5x a do animal atrelado, MENOS o peso do veiculo (PHB)' do
    sheet_dono.update!(companions: [
      { 'id' => 'mnt-1', 'name' => 'Mula', 'type' => 'mount', 'carryCapacity' => 420 },
    ])
    criar_carroca!(h_dono, mounts: [{ sheet_id: sheet_dono.id, companion_id: 'mnt-1' }])

    get "/api/v1/player/groups/#{group.id}/carts", headers: h_dono, as: :json

    # 420 * 5 = 2100, menos 220 do veiculo
    expect(response.parsed_body['carts'].first['capacity_lb']).to eq(1880)
  end

  it 'REGRESSAO: sem animal atrelado a capacidade e ZERO — carroça parada nao carrega' do
    criar_carroca!

    get "/api/v1/player/groups/#{group.id}/carts", headers: h_dono, as: :json

    expect(response.parsed_body['carts'].first['capacity_lb']).to eq(0)
  end

  it 'REGRESSAO: apagar a carroça DEVOLVE a carga a cada dono' do
    criar_carroca!
    it_dono = item!(sheet_dono)
    it_colega = item!(sheet_colega, nome: 'Tenda')
    guardar(it_dono, h_dono)
    guardar(it_colega, h_colega)

    delete "/api/v1/player/groups/#{group.id}/carts/cart-1", headers: h_dono, as: :json

    expect(response).to have_http_status(:ok)
    expect(SheetItem.find_by(id: it_dono.id)).to be_present
    expect(prop(it_dono)).to be_nil
    expect(prop(it_colega)).to be_nil
  end

  it 'REGRESSAO: o peso da carga vem de props_json, nao de uma chave que nao existe' do
    criar_carroca!
    guardar(item!(sheet_dono, nome: 'Barril', qtd: 3, peso: 10), h_dono)

    get "/api/v1/player/groups/#{group.id}/carts/cart-1/items", headers: h_dono, as: :json

    body = response.parsed_body
    expect(body['items'].first['weight_lb']).to eq(10.0)
    expect(body['carried_lb']).to eq(30.0)
  end

  it 'a carroça diz QUEM a puxa, sem a ficha alheia carregada' do
    sheet_dono.update!(companions: [
      { 'id' => 'mnt-1', 'name' => 'Mula', 'type' => 'mount', 'carryCapacity' => 420 },
    ])
    criar_carroca!(h_dono, mounts: [{ sheet_id: sheet_dono.id, companion_id: 'mnt-1' }])

    get "/api/v1/player/groups/#{group.id}/carts", headers: h_colega, as: :json

    expect(response.parsed_body['carts'].first['mounts'].first['name']).to eq('Mula')
  end

  it 'item de OUTRO grupo nao entra nesta carroça' do
    criar_carroca!
    outro_pc = create(:character, user: create(:user), name: 'Alheio')
    alheio = item!(create(:sheet, character: outro_pc))

    guardar(alheio, h_dono)

    expect(response).to have_http_status(:not_found)
    expect(prop(alheio)).to be_nil
  end
end
