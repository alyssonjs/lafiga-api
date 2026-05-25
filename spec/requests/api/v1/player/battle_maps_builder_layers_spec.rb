# frozen_string_literal: true

require 'rails_helper'

# Fase 2.0 — Map Builder (Inkarnate-style). Cobre o contrato HTTP das
# camadas novas: PATCH persiste layers/terrain_layers/stamps/paths/
# map_effects/map_kind e o serializer devolve em camelCase no :full.
# Mapas legados (sem esses campos) continuam idênticos (arrays vazios).
RSpec.describe 'Api::V1::Player::BattleMaps builder layers', type: :request do
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:user)        { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(user) }

  let(:stamp) do
    {
      'id' => 'st1', 'assetId' => 'mountain-01',
      'x' => 320.0, 'y' => 160.0, 'rotation' => 15,
      'scaleX' => 1.2, 'scaleY' => 1.2, 'opacity' => 1, 'z' => 1,
    }
  end
  let(:terrain_layer) do
    {
      'id' => 'T1', 'name' => 'Grama', 'assetId' => 'grass',
      'visible' => true, 'locked' => false, 'opacity' => 1, 'strokes' => [],
    }
  end

  it 'owner persiste todas as camadas do builder e recebe camelCase no :full' do
    m = create(:battle_map, user: user)

    patch "/api/v1/player/battle_maps/#{m.id}",
          params: { battle_map: {
            map_kind: 'world',
            layers: [{ 'id' => 'L1', 'type' => 'stamps', 'name' => 'Objetos',
                       'visible' => true, 'locked' => false, 'opacity' => 1, 'z' => 1 }],
            terrain_layers: [terrain_layer],
            stamps: [stamp],
            paths: [{ 'id' => 'P1', 'kind' => 'river',
                      'points' => [{ 'x' => 0, 'y' => 0 }, { 'x' => 5, 'y' => 5 }],
                      'widthPx' => 8, 'z' => 1 }],
            map_effects: { 'vignette' => 0.3 },
          } },
          headers: headers, as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    body = response.parsed_body['battle_map']
    expect(body['mapKind']).to eq('world')
    expect(body['stamps'].first['assetId']).to eq('mountain-01')
    expect(body['terrainLayers'].first['id']).to eq('T1')
    expect(body['paths'].first['kind']).to eq('river')
    expect(body['mapEffects']).to eq('vignette' => 0.3)

    m.reload
    expect(m.map_kind).to eq('world')
    expect(m.stamps.first['assetId']).to eq('mountain-01')
    expect(m.terrain_layers.first['name']).to eq('Grama')
  end

  it 'mapa legado serializa builder vazio (back-compat) e mapKind battle' do
    m = create(:battle_map, user: user)
    get "/api/v1/player/battle_maps/#{m.id}", headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body['battle_map']
    expect(body['mapKind']).to eq('battle')
    expect(body['layers']).to eq([])
    expect(body['terrainLayers']).to eq([])
    expect(body['stamps']).to eq([])
    expect(body['paths']).to eq([])
    expect(body['mapEffects']).to eq({})
  end

  it 'lista SLIM traz mapKind mas omite os blobs do builder (payload enxuto)' do
    create(:battle_map, user: user, map_kind: 'world', stamps: [stamp])
    get '/api/v1/player/battle_maps', headers: headers

    expect(response).to have_http_status(:ok)
    row = response.parsed_body['battle_maps'].first
    expect(row['mapKind']).to eq('world')
    expect(row).not_to have_key('stamps')
    expect(row).not_to have_key('terrainLayers')
  end

  it 'rejeita map_kind invalido (422)' do
    m = create(:battle_map, user: user)
    patch "/api/v1/player/battle_maps/#{m.id}",
          params: { battle_map: { map_kind: 'lixo' } },
          headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejeita stamp malformado (sem assetId) — defesa em profundidade' do
    m = create(:battle_map, user: user)
    patch "/api/v1/player/battle_maps/#{m.id}",
          params: { battle_map: { stamps: [{ 'id' => 'x', 'x' => 1, 'y' => 2 }] } },
          headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
