# frozen_string_literal: true

require 'rails_helper'

# A API de BLOCO (L1.2; plano B3 e B8): o jogador carrega os blocos em volta de onde está. O roteiro do roadmap:
# "carrega os 9 blocos em volta do jogador".
RSpec.describe 'Api::V1::Player::MapaBlocosController', type: :request do
  let(:jogador)  { create(:user) }
  let(:estranho) { create(:user) }
  let(:group)    { create(:group) }
  let!(:pc)      { create(:character, user: jogador, group: group) }
  let(:mapa)     { create(:battle_map, :vila, group: group) } # 100×100 = 3×3 blocos

  before do
    (0..2).each { |bl| (0..2).each { |bc| create(:mapa_bloco, battle_map: mapa, bc: bc, bl: bl) } }
  end

  def blocos(headers: bearer_headers_for(jogador), id: mapa.id, **params)
    get "/api/v1/player/battle_maps/#{id}/blocos", params: params, headers: headers
  end

  def lugares
    response.parsed_body['blocos'].map { |b| [b['bc'], b['bl']] }
  end

  it 'devolve os 9 blocos em volta do bloco do jogador' do
    blocos(bc: 1, bl: 1)

    expect(response).to have_http_status(:ok)
    expect(lugares).to eq([[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [0, 2], [1, 2], [2, 2]])
    expect(response.parsed_body['meta']).to eq('lado' => 40, 'colunas' => 100, 'linhas' => 100, 'total' => 9)
    expect(response.parsed_body['blocos'].first.keys).to contain_exactly('bc', 'bl', 'versao', 'terreno', 'objetos')
  end

  it 'no canto, a janela é cortada pela borda do mapa' do
    blocos(bc: 0, bl: 0)

    expect(lugares).to eq([[0, 0], [1, 0], [0, 1], [1, 1]])
  end

  it 'com raio 0, só o bloco pedido (o que o bloco_mudou recarrega)' do
    blocos(bc: 2, bl: 1, raio: 0)

    expect(lugares).to eq([[2, 1]])
  end

  it 'quem não pode ler o mapa não lê os blocos' do
    blocos(bc: 1, bl: 1, headers: bearer_headers_for(estranho))

    expect(response).to have_http_status(:forbidden)
  end

  it 'mapa que não existe é 404; mapa que não é em blocos é 422' do
    blocos(bc: 0, bl: 0, id: 0)
    expect(response).to have_http_status(:not_found)

    inteiro = create(:battle_map, group: group)
    blocos(bc: 0, bl: 0, id: inteiro.id)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'recusa raio fora de 0 a 2 e bloco que não é inteiro' do
    blocos(bc: 1, bl: 1, raio: 3)
    expect(response).to have_http_status(:unprocessable_entity)

    blocos(bc: 'meio', bl: 1)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors']).to be_present
  end

  it 'pede login' do
    get "/api/v1/player/battle_maps/#{mapa.id}/blocos", params: { bc: 0, bl: 0 }

    expect(response).to have_http_status(:unauthorized)
  end
end
