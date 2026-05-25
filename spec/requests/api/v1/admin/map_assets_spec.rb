# frozen_string_literal: true

require 'rails_helper'

# Fase 2.6 — biblioteca de assets do Map Builder (upload do DM).
# Cobre auth (DM site-wide), upload multipart (ActiveStorage), contrato
# JSON camelCase, listagem/filtro por kind, update e destroy.
RSpec.describe 'Api::V1::Admin::MapAssets', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm)          { create(:user, role: dm_role) }
  let(:player)      { create(:user, role: player_role) }

  let(:png) do
    Rack::Test::UploadedFile.new(
      StringIO.new("\x89PNG\r\n\x1a\nfake"),
      'image/png',
      original_filename: 'grama.png',
    )
  end

  it 'DM cria asset com upload e recebe contrato camelCase + imageUrl de blob' do
    post '/api/v1/admin/map_assets',
         params: { map_asset: {
           name: 'Grama Custom', kind: 'texture', category: 'vegetacao',
           color: '#4a7c45', image: png
         } },
         headers: bearer_headers_for(dm).except('CONTENT_TYPE')

    expect(response).to have_http_status(:created), -> { response.body }
    a = response.parsed_body['map_asset']
    expect(a['name']).to eq('Grama Custom')
    expect(a['kind']).to eq('texture')
    expect(a['userId']).to eq(dm.id)
    expect(a['enabled']).to eq(true)
    expect(a['imageUrl']).to include('rails/active_storage/blobs')
    expect(MapAsset.last.image).to be_attached
  end

  it 'rejeita player não-DM (403/401)' do
    post '/api/v1/admin/map_assets',
         params: { map_asset: { name: 'X', kind: 'stamp', category: 'custom', image: png } },
         headers: bearer_headers_for(player).except('CONTENT_TYPE')
    expect(response.status).to be_in([401, 403])
    expect(MapAsset.count).to eq(0)
  end

  it 'rejeita kind inválido (422) e asset sem imagem (422)' do
    post '/api/v1/admin/map_assets',
         params: { map_asset: { name: 'X', kind: 'lixo', category: 'c', image: png } },
         headers: bearer_headers_for(dm).except('CONTENT_TYPE')
    expect(response).to have_http_status(:unprocessable_entity)

    post '/api/v1/admin/map_assets',
         params: { map_asset: { name: 'Sem img', kind: 'texture', category: 'c' } },
         headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lista todos e filtra por kind' do
    a1 = create(:map_asset, :texture, user: dm)
    a2 = create(:map_asset, :stamp, user: dm)

    get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body['map_assets'].map { |x| x['id'] }
    expect(ids).to include(a1.id, a2.id)

    get '/api/v1/admin/map_assets', params: { kind: 'stamp' }, headers: bearer_headers_for(dm)
    ids = response.parsed_body['map_assets'].map { |x| x['id'] }
    expect(ids).to eq([a2.id])
  end

  it 'DM atualiza (rename/enabled) e remove' do
    a = create(:map_asset, :texture, user: dm)

    patch "/api/v1/admin/map_assets/#{a.id}",
          params: { map_asset: { name: 'Renomeado', enabled: false } },
          headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:ok)
    expect(a.reload.name).to eq('Renomeado')
    expect(a.enabled).to eq(false)

    delete "/api/v1/admin/map_assets/#{a.id}", headers: bearer_headers_for(dm)
    expect(response).to have_http_status(:ok)
    expect(MapAsset.find_by(id: a.id)).to be_nil
  end
end
