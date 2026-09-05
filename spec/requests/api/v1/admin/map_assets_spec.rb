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
    # imageUrl aponta p/ o endpoint próprio com cache imutável (map_assets#image),
    # não mais o redirect do ActiveStorage.
    expect(a['imageUrl']).to include("/api/v1/admin/map_assets/#{MapAsset.last.id}/image")
    expect(MapAsset.last.image).to be_attached
  end

  it 'serve a imagem pelo endpoint próprio (PÚBLICO, sem auth) com cache imutável' do
    asset = MapAsset.new(name: 'Pedra', kind: 'object', category: 'Rochas', color: '#888888')
    asset.image.attach(io: StringIO.new("\x89PNG\r\n\x1a\nfake"), filename: 'p.png', content_type: 'image/png')
    asset.save!

    get "/api/v1/admin/map_assets/#{asset.id}/image" # sem headers de auth

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include('image/png')
    expect(response.headers['Cache-Control']).to include('public')
    expect(response.headers['Cache-Control']).to include('immutable')
    expect(response.body.bytesize).to be > 0
  end

  it 'image → 404 para asset inexistente' do
    get '/api/v1/admin/map_assets/999999/image'
    expect(response).to have_http_status(:not_found)
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

  # O front sabe que uma textura veio do catálogo do Inkarnate (80 células por
  # repetição, seamless) só pelo nome do arquivo que a rake carimbou no anexo.
  describe 'sourceRef no contrato' do
    it 'expõe o nome do arquivo sem extensão p/ anexo importado do catálogo', :aggregate_failures do
      tex = MapAsset.new(name: 'Green Light', kind: 'texture', category: 'Watercolor Cities')
      tex.image.attach(io: StringIO.new('jpg-fake'), filename: 'inktex-594921.jpg', content_type: 'image/jpeg')
      tex.save!
      obj = MapAsset.new(name: 'Pedra', kind: 'object', category: 'Fantasy Battlemaps')
      obj.image.attach(io: StringIO.new('png-fake'), filename: 'ink-12345.png', content_type: 'image/png')
      obj.save!

      get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      por_id = response.parsed_body['map_assets'].index_by { |x| x['id'] }
      expect(por_id[tex.id]['sourceRef']).to eq('inktex-594921')
      expect(por_id[obj.id]['sourceRef']).to eq('ink-12345')
    end

    it 'é nil p/ upload do utilizador (o nome do arquivo dele não é referência de origem)' do
      a = create(:map_asset, :texture, user: dm) # anexa 'asset.png'

      get '/api/v1/admin/map_assets', params: { kind: 'texture' }, headers: bearer_headers_for(dm)

      rec = response.parsed_body['map_assets'].find { |x| x['id'] == a.id }
      expect(rec).to have_key('sourceRef')
      expect(rec['sourceRef']).to be_nil
    end
  end

  # Sombra por stamp do catálogo (meta['shadow']): 'none' = arte com sombra
  # pintada; {b,x,y,i} = receita custom em unidades de cena (200/célula);
  # ausente = o front usa o padrão do estilo.
  describe 'shadow no contrato' do
    it 'expõe o meta.shadow como veio do catálogo, e nil sem meta', :aggregate_failures do
      sem = create(:map_asset, :texture, user: dm)
      none = MapAsset.new(name: 'Morro', kind: 'object', category: 'Fantasy Battlemaps',
                          meta: { 'shadow' => 'none' })
      none.image.attach(io: StringIO.new('png-fake'), filename: 'ink-1.png', content_type: 'image/png')
      none.save!
      custom = MapAsset.new(name: 'Tenda', kind: 'object', category: 'Fantasy Battlemaps',
                            meta: { 'shadow' => { 'b' => 88, 'x' => 32, 'y' => 32, 'i' => 0.6 } })
      custom.image.attach(io: StringIO.new('png-fake'), filename: 'ink-2.png', content_type: 'image/png')
      custom.save!

      get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)

      por_id = response.parsed_body['map_assets'].index_by { |x| x['id'] }
      expect(por_id[sem.id]['shadow']).to be_nil
      expect(por_id[none.id]['shadow']).to eq('none')
      expect(por_id[custom.id]['shadow']).to eq({ 'b' => 88, 'x' => 32, 'y' => 32, 'i' => 0.6 })
    end
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

  # O objeto de cenario do mapa carrega esta URL no token. Se o arquivo sumir do
  # storage, um 500 aqui vira objeto INVISIVEL no mapa do jogador, sem pista
  # nenhuma para quem esta jogando.
  describe 'GET /image quando o arquivo sumiu do storage' do
    # A imagem e obrigatoria no model: anexa ANTES de salvar.
    let!(:asset) do
      a = MapAsset.new(name: 'Pedra', kind: 'object')
      a.image.attach(io: StringIO.new('conteudo-fake'), filename: 'p.png', content_type: 'image/png')
      a.save!
      a
    end

    it 'serve normalmente quando o arquivo existe (sem exigir auth de DM)' do
      get "/api/v1/admin/map_assets/#{asset.id}/image"

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('conteudo-fake')
    end

    it 'REGRESSAO: arquivo ausente responde 404, nao 500' do
      blob = asset.image.blob
      blob.service.delete(blob.key)

      get "/api/v1/admin/map_assets/#{asset.id}/image"

      expect(response).to have_http_status(:not_found)
    end
  end
end
