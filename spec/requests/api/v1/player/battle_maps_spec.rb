# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::BattleMapsController', type: :request do
  let(:player_role) { create(:role, name: 'Player') }
  let(:dm_role)     { create(:role, name: 'DM') }
  let(:user)        { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(user) }

  def cells_5x5(fill = 'empty')
    Array.new(5) { Array.new(5, fill) }
  end

  def base_payload(over = {})
    {
      battle_map: {
        name: 'Cripta',
        width: 5, height: 5, cell_size_px: 32,
        cells: cells_5x5,
        tokens: [],
      }.merge(over),
    }
  end

  describe 'GET /api/v1/player/battle_maps' do
    it 'lista mapas proprios + compartilhados via group, em modo SLIM (sem cells)' do
      mine = create(:battle_map, user: user)
      group = create(:group)
      create(:character, user: user, group: group)
      shared = create(:battle_map, user: create(:user, role: player_role), group: group)
      stranger_map = create(:battle_map, user: create(:user, role: player_role))

      get '/api/v1/player/battle_maps', headers: headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['battle_maps'].map { |m| m['id'] }
      expect(ids).to include(mine.id, shared.id)
      expect(ids).not_to include(stranger_map.id)

      first = response.parsed_body['battle_maps'].first
      expect(first).to have_key('cellSizePx')
      expect(first).to have_key('cellWorldFt')
      expect(first).not_to have_key('cells')
    end

    it 'DM ve todos os mapas' do
      dm = create(:user, role: dm_role)
      a = create(:battle_map, user: user)
      b = create(:battle_map, user: create(:user, role: player_role))
      get '/api/v1/player/battle_maps', headers: bearer_headers_for(dm)
      ids = response.parsed_body['battle_maps'].map { |m| m['id'] }
      expect(ids).to include(a.id, b.id)
    end

    it 'inclui mapa do mestre sem group_id quando vinculado a Schedule do grupo do jogador' do
      dm = create(:user, role: dm_role)
      group = create(:group)
      create(:character, user: user, group: group)
      dm_map = create(:battle_map, user: dm, group: nil)
      create(:schedule, group: group, battle_map: dm_map)

      get '/api/v1/player/battle_maps', headers: headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['battle_maps'].map { |m| m['id'] }
      expect(ids).to include(dm_map.id)
    end
  end

  describe 'GET /api/v1/player/battle_maps/:id' do
    it 'retorna FULL payload (com cells) quando readable' do
      m = create(:battle_map, user: user)
      get "/api/v1/player/battle_maps/#{m.id}", headers: headers
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['battle_map']
      expect(payload['cells']).to be_an(Array)
      expect(payload['width']).to eq(5)
    end

    it 'retorna 403 para nao-membro' do
      stranger = create(:user, role: player_role)
      m = create(:battle_map, user: stranger)
      get "/api/v1/player/battle_maps/#{m.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'permite leitura quando o mapa so do mestre (sem group) esta vinculado a sessao do grupo' do
      dm = create(:user, role: dm_role)
      group = create(:group)
      create(:character, user: user, group: group)
      dm_map = create(:battle_map, user: dm, group: nil)
      create(:schedule, group: group, battle_map: dm_map)

      get "/api/v1/player/battle_maps/#{dm_map.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['battle_map']['id']).to eq(dm_map.id)
    end

    it 'permite leitura a jogador autenticado fora do grupo quando o mapa esta vinculado a uma sessao' do
      dm = create(:user, role: dm_role)
      group = create(:group)
      dm_map = create(:battle_map, user: dm, group: nil)
      create(:schedule, group: group, battle_map: dm_map)
      stranger = create(:user, role: player_role)

      get "/api/v1/player/battle_maps/#{dm_map.id}", headers: bearer_headers_for(stranger)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['battle_map']['id']).to eq(dm_map.id)
    end
  end

  describe 'POST /api/v1/player/battle_maps' do
    it 'cria mapa com user_id = current_user' do
      post '/api/v1/player/battle_maps', params: base_payload, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      payload = response.parsed_body['battle_map']
      expect(payload['userId']).to eq(user.id)
      expect(payload['name']).to eq('Cripta')
    end

    it 'rejeita 422 quando cells matrix tem dimensoes erradas' do
      post '/api/v1/player/battle_maps',
           params: base_payload(cells: Array.new(3) { Array.new(5, 'empty') }),
           headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/player/battle_maps/:id' do
    it 'owner pode atualizar' do
      m = create(:battle_map, user: user)
      patch "/api/v1/player/battle_maps/#{m.id}",
            params: { battle_map: { name: 'Renomeado' } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['battle_map']['name']).to eq('Renomeado')
    end

    it 'owner pode persistir cell_world_ft valido (multiplo de 5) e responde cellWorldFt' do
      m = create(:battle_map, user: user)
      patch "/api/v1/player/battle_maps/#{m.id}",
            params: { battle_map: { cell_world_ft: 10 } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['battle_map']['cellWorldFt'].to_f).to eq(10.0)
      expect(m.reload.cell_world_ft.to_f).to eq(10.0)
    end

    it 'rejeita cell_world_ft fora da lista permitida' do
      m = create(:battle_map, user: user)
      patch "/api/v1/player/battle_maps/#{m.id}",
            params: { battle_map: { cell_world_ft: 7 } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'non-owner non-DM recebe 403' do
      stranger = create(:user, role: player_role)
      m = create(:battle_map, user: stranger)
      patch "/api/v1/player/battle_maps/#{m.id}",
            params: { battle_map: { name: 'Hack' } },
            headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'membro do grupo pode acrescentar aoe_placements quando aoe esta liberado' do
      dm = create(:user, role: dm_role)
      group = create(:group)
      viewer = create(:user, role: player_role)
      create(:character, user: viewer, group: group)
      m = create(
        :battle_map,
        user: dm,
        group: group,
        aoe_placements: [],
        player_permissions: { 'measure' => true, 'pencil' => false, 'aoe' => true },
      )
      new_pl = [
        {
          'id' => 'p1', 'shape' => 'sphere', 'sizeFt' => 20,
          'origin' => { 'col' => 1, 'row' => 1 },
          'cells' => [{ 'col' => 1, 'row' => 1 }],
          'color' => '#C93B3B',
        },
      ]
      patch "/api/v1/player/battle_maps/#{m.id}",
            params: { battle_map: { aoe_placements: new_pl } },
            headers: bearer_headers_for(viewer), as: :json
      expect(response).to have_http_status(:ok)
      expect(m.reload.aoe_placements.size).to eq(1)
      expect(m.aoe_placements.first['id']).to eq('p1')
    end

    it 'membro do grupo nao pode remover aoe_placements existentes (anti-grief)' do
      dm = create(:user, role: dm_role)
      group = create(:group)
      viewer = create(:user, role: player_role)
      create(:character, user: viewer, group: group)
      existing = [
        {
          'id' => 'dm1', 'shape' => 'sphere', 'sizeFt' => 20,
          'origin' => { 'col' => 0, 'row' => 0 },
          'cells' => [{ 'col' => 0, 'row' => 0 }],
          'color' => '#C93B3B',
        },
      ]
      m = create(
        :battle_map,
        user: dm,
        group: group,
        aoe_placements: existing,
        player_permissions: { 'measure' => true, 'pencil' => false, 'aoe' => true },
      )
      patch "/api/v1/player/battle_maps/#{m.id}",
            params: { battle_map: { aoe_placements: [] } },
            headers: bearer_headers_for(viewer), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v1/player/battle_maps/:id' do
    it 'owner deleta' do
      m = create(:battle_map, user: user)
      delete "/api/v1/player/battle_maps/#{m.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(BattleMap.find_by(id: m.id)).to be_nil
    end
  end

  describe 'POST /api/v1/player/battle_maps/:id/duplicate' do
    it 'cria copia com nome "(Copia)" e novo id' do
      m = create(:battle_map, :with_tokens, user: user, name: 'Original')
      post "/api/v1/player/battle_maps/#{m.id}/duplicate", headers: headers
      expect(response).to have_http_status(:created)
      payload = response.parsed_body['battle_map']
      expect(payload['id']).not_to eq(m.id)
      expect(payload['name']).to eq('Original (Copia)')
      expect(payload['tokens'].size).to eq(1)
    end
  end

  describe 'POST /api/v1/player/battle_maps/import_legacy' do
    it 'importa mapas vindos do localStorage do front (camelCase)' do
      payload = {
        battle_maps: [
          {
            id: 'local-1', name: 'Local Cripta',
            width: 5, height: 5, cellSizePx: 32,
            cells: cells_5x5, tokens: [],
            createdAt: Time.current.iso8601, updatedAt: Time.current.iso8601,
          },
        ],
      }
      expect {
        post '/api/v1/player/battle_maps/import_legacy', params: payload, headers: headers, as: :json
      }.to change(BattleMap, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['imported'].size).to eq(1)
    end

    it 'e idempotente por (user_id + name + createdAt)' do
      iso = Time.current.iso8601
      base = {
        id: 'local-1', name: 'Cripta',
        width: 5, height: 5, cellSizePx: 32,
        cells: cells_5x5, tokens: [],
        createdAt: iso, updatedAt: iso,
      }
      post '/api/v1/player/battle_maps/import_legacy',
           params: { battle_maps: [base] }, headers: headers, as: :json
      expect {
        post '/api/v1/player/battle_maps/import_legacy',
             params: { battle_maps: [base] }, headers: headers, as: :json
      }.not_to change(BattleMap, :count)
    end
  end

  describe 'POST /api/v1/player/battle_maps/:id/move_token' do
    let(:character) { create(:character, user: user) }
    let(:map) do
      create(:battle_map, user: user, tokens: [
        { 'id' => 't-mine', 'name' => 'Eu', 'color' => '#fff', 'x' => 0, 'y' => 0, 'size' => 1, 'characterId' => character.id.to_s },
        { 'id' => 't-npc', 'name' => 'NPC', 'color' => '#000', 'x' => 1, 'y' => 1, 'size' => 1 },
      ])
    end

    it 'player pode mover token vinculado a um Character proprio' do
      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { token_id: 't-mine', x: 2, y: 3 }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      moved = response.parsed_body['battle_map']['tokens'].find { |t| t['id'] == 't-mine' }
      expect(moved['x']).to eq(2)
      expect(moved['y']).to eq(3)
    end

    it 'player nao pode mover token sem characterId (NPC)' do
      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { token_id: 't-npc', x: 2, y: 2 }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'rejeita coordenadas fora do mapa' do
      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { token_id: 't-mine', x: 99, y: 0 }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'DM pode mover qualquer token (incluindo sem characterId)' do
      dm = create(:user, role: dm_role)
      post "/api/v1/player/battle_maps/#{map.id}/move_token",
           params: { token_id: 't-npc', x: 2, y: 2 }, headers: bearer_headers_for(dm), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
