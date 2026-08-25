# frozen_string_literal: true

require 'rails_helper'

# Camada de MESA: o mesmo mapa em duas sessões nao pode compartilhar tokens de
# criatura nem nevoa. O CENARIO (objetos, `assetId`) continua sendo do mapa.
RSpec.describe 'Api::V1::Player::BattleMaps camada de sessao', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm)          { create(:user, role: dm_role) }
  let(:intruso)     { create(:user, role: player_role) }

  let(:grupo_a) { create(:group, dm_user: dm) }
  let(:grupo_b) { create(:group, dm_user: dm) }
  let(:sessao_a) { create(:schedule, group: grupo_a, created_by_user: dm) }
  let(:sessao_b) { create(:schedule, group: grupo_b, created_by_user: dm) }

  let(:cenario)  { { 'id' => 'obj-1', 'assetId' => 7, 'x' => 1, 'y' => 1 } }
  let(:heroi_a)  { { 'id' => 'tk-a', 'characterId' => '101', 'x' => 2, 'y' => 2 } }
  let(:heroi_b)  { { 'id' => 'tk-b', 'characterId' => '202', 'x' => 3, 'y' => 3 } }

  let(:map) { create(:battle_map, user: dm, tokens: [cenario]) }

  # O mapa da factory e 5x5 — a nevoa precisa desse formato (validado nos dois
  # lados). `reveladas` = quantas celulas da primeira linha ficam reveladas.
  def fog_grid(reveladas = 0)
    Array.new(5) { |y| Array.new(5) { |x| y.zero? && x < reveladas } }
  end

  def link!(schedule, tokens:, fog: [])
    ScheduleBattleMap.create!(schedule: schedule, battle_map: map, position: 0,
                              tokens: tokens, fog: fog)
  end

  def show(schedule_id: nil, as: dm)
    params = schedule_id ? { schedule_id: schedule_id } : {}
    get "/api/v1/player/battle_maps/#{map.id}", params: params, headers: bearer_headers_for(as)
    response.parsed_body['battle_map']
  end

  it 'cada sessao ve so as SUAS criaturas, mais o cenario do mapa' do
    link!(sessao_a, tokens: [heroi_a], fog: fog_grid(1))
    link!(sessao_b, tokens: [heroi_b], fog: fog_grid(3))

    ids_a = show(schedule_id: sessao_a.id)['tokens'].map { |t| t['id'] }
    ids_b = show(schedule_id: sessao_b.id)['tokens'].map { |t| t['id'] }

    expect(ids_a).to contain_exactly('obj-1', 'tk-a')
    expect(ids_b).to contain_exactly('obj-1', 'tk-b')
  end

  it 'REGRESSAO: a nevoa de uma mesa nao vaza para a outra' do
    link!(sessao_a, tokens: [], fog: fog_grid(4))
    link!(sessao_b, tokens: [], fog: [])

    reveladas = ->(f) { Array(f).flatten.count(true) }
    expect(reveladas.(show(schedule_id: sessao_a.id)['fog'])).to eq(4)
    expect(reveladas.(show(schedule_id: sessao_b.id)['fog'])).to eq(0)
  end

  it 'sem schedule_id devolve o mapa cru — e o tabuleiro do Map Builder' do
    link!(sessao_a, tokens: [heroi_a])

    expect(show['tokens'].map { |t| t['id'] }).to contain_exactly('obj-1')
  end

  it 'schedule_id de sessao que o usuario nao le e IGNORADO (nao espia a outra mesa)' do
    link!(sessao_a, tokens: [heroi_a], fog: fog_grid(2))
    # `intruso` nao tem personagem no grupo nem e dono da mesa.
    map.update!(user_id: intruso.id)

    body = show(schedule_id: sessao_a.id, as: intruso)

    expect(body['tokens'].map { |t| t['id'] }).to contain_exactly('obj-1')
    expect(body['fog']).to be_nil.or eq([])
  end

  it 'schedule_id sem vinculo com este mapa nao quebra' do
    outro = create(:schedule, group: grupo_a, created_by_user: dm)

    expect { show(schedule_id: outro.id) }.not_to raise_error
    expect(response).to have_http_status(:ok)
  end

  describe 'discriminador cenario x criatura' do
    it 'classifica por characterId/npcId' do
      expect(BattleMap.creature_token?('characterId' => '1')).to be(true)
      expect(BattleMap.creature_token?('npcId' => 'n1')).to be(true)
      expect(BattleMap.creature_token?('assetId' => 7)).to be(false)
      expect(BattleMap.creature_token?('characterId' => '')).to be(false)
    end
  end

  describe 'escrita com schedule_id' do
    let!(:link_a) { link!(sessao_a, tokens: [heroi_a]) }
    let!(:link_b) { link!(sessao_b, tokens: [heroi_b]) }

    it 'REGRESSAO: revelar nevoa numa mesa nao revela na outra' do
      patch "/api/v1/player/battle_maps/#{map.id}",
            params: { schedule_id: sessao_a.id, battle_map: { fog: fog_grid(5) } },
            headers: bearer_headers_for(dm), as: :json

      expect(response).to have_http_status(:ok)
      expect(Array(link_a.reload.fog).flatten.count(true)).to eq(5)
      expect(link_b.reload.fog).to be_blank
      expect(map.reload.fog).to be_nil
    end

    it 'mover token numa mesa nao move na outra' do
      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { schedule_id: sessao_a.id, token_id: 'tk-a', x: 4, y: 4 },
           headers: bearer_headers_for(dm), as: :json

      expect(response).to have_http_status(:ok)
      expect(link_a.reload.tokens.first['x']).to eq(4)
      # heroi_b nasce em x=3: o invariante e ele NAO ter se mexido.
      expect(link_b.reload.tokens.first['x']).to eq(3)
      expect(map.reload.tokens.map { |t| t['id'] }).to contain_exactly('obj-1')
    end

    it 'REGRESSAO: a RESPOSTA do move sai da CAMADA, nao do original' do
      # O bug real de 25/08: a escrita ia para a camada e a resposta era
      # serializada do MAPA — o front reconciliava com os tokens do original e
      # o token "voltava sozinho" para quem o moveu (reload mostrava o certo).
      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { schedule_id: sessao_a.id, token_id: 'tk-a', x: 4, y: 4 },
           headers: bearer_headers_for(dm), as: :json

      corpo = response.parsed_body['battle_map']['tokens']
      movido = corpo.find { |t| t['id'] == 'tk-a' }
      expect(movido).not_to be_nil, 'o heroi da camada tem de estar na resposta'
      expect(movido.values_at('x', 'y')).to eq([4, 4])
      # O cenario do mapa continua vindo junto (merge, nao substituicao).
      expect(corpo.map { |t| t['id'] }).to include('obj-1')
    end

    it 'REGRESSAO: mesmo id nos DOIS lugares — a posicao da CAMADA vence' do
      # Cenario exato da sessao 71: camada semeada do original, entao o mesmo
      # token existe nos dois com posicoes divergentes apos o move.
      map.update!(tokens: [cenario, heroi_a.merge('x' => 9, 'y' => 9)])

      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { schedule_id: sessao_a.id, token_id: 'tk-a', x: 4, y: 4 },
           headers: bearer_headers_for(dm), as: :json

      movido = response.parsed_body['battle_map']['tokens'].find { |t| t['id'] == 'tk-a' }
      expect(movido.values_at('x', 'y')).to eq([4, 4])
    end

    it 'sem schedule_id continua gravando no mapa (Map Builder)' do
      patch "/api/v1/player/battle_maps/#{map.id}",
            params: { battle_map: { fog: fog_grid(2) } },
            headers: bearer_headers_for(dm), as: :json

      expect(Array(map.reload.fog).flatten.count(true)).to eq(2)
    end
  end
end
