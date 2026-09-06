# frozen_string_literal: true

require 'rails_helper'

# MINIATURA da biblioteca de itens.
#
# A grelha mostra o objeto num quadrado de ~100 px e, sem miniatura, cada card
# baixava a ARTE: medido em prod, 254 KB e ~300 px por card — uma busca de 400
# cards custava 68 MB. Estes exemplos prendem o contrato que evita a volta disso.
RSpec.describe 'Api::V1::Admin::MapAssets thumb', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }

  let(:asset) do
    a = MapAsset.new(name: 'Arvore', kind: 'object', category: 'Fantasy', enabled: true)
    a.image.attach(io: StringIO.new("\x89PNG\r\n\x1a\narte-grande"),
                   filename: 'ink-42.png', content_type: 'image/png')
    a.save!
    a
  end

  def anexa_miniatura!
    asset.thumb.attach(io: StringIO.new('RIFFwebp-mini'),
                       filename: 'ink-42.webp', content_type: 'image/webp')
    asset
  end

  it 'serve a miniatura SEM auth e com cache imutável (o card é público)' do
    anexa_miniatura!
    get "/api/v1/admin/map_assets/#{asset.id}/thumb?v=#{asset.thumb.blob.id}"

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include('image/webp')
    expect(response.body).to eq('RIFFwebp-mini')
    # `?v=` é o id do blob → o cache pode ser eterno e invalida-se sozinho
    expect(response.headers['Cache-Control']).to include('immutable')
  end

  it '⚠️ 404 quando não há miniatura — NUNCA cai na arte cheia' do
    # servir a arte aqui derrotaria o propósito (254 KB num card de 100 px) e
    # esconderia que a miniatura falta; o front decide o recuo, com o dado à vista
    get "/api/v1/admin/map_assets/#{asset.id}/thumb"

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('arte-grande')
  end

  it 'o serializer expõe thumbUrl só quando existe; senão nil (front usa imageUrl)' do
    sem = MapAssetSerializer.serialize(asset)
    expect(sem[:thumbUrl]).to be_nil
    expect(sem[:imageUrl]).to be_present

    anexa_miniatura!
    com = MapAssetSerializer.serialize(asset.reload)
    expect(com[:thumbUrl]).to eq("/api/v1/admin/map_assets/#{asset.id}/thumb?v=#{asset.thumb.blob.id}")
    # a arte continua servida — colocar no mapa usa a imagem cheia
    expect(com[:imageUrl]).to be_present
  end

  it 'a listagem traz thumbUrl e faz eager-load do thumb (sem N+1)' do
    anexa_miniatura!
    get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)

    expect(response).to have_http_status(:ok)
    registo = JSON.parse(response.body)['map_assets'].find { |r| r['id'] == asset.id }
    expect(registo['thumbUrl']).to be_present
    # o eager-load é o que impede a listagem de voltar a fazer 2 queries por item
    expect(MapAsset.with_attached_image.with_attached_thumb.to_sql).to be_a(String)
  end
end

# A biblioteca pede o catálogo INTEIRO (a busca do painel varre tudo no
# cliente). Em prod são 16.595 objetos e 6,84 MB: 4,0 s a carregar + 3,6 s a
# serializar + 3,1 s no to_json, com o browser a esperar ~17 s. Recalcular isso
# a cada abertura é o desperdício — o catálogo só muda quando alguém o edita.
RSpec.describe 'Api::V1::Admin::MapAssets index cache', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }

  def cria_asset(nome)
    a = MapAsset.new(name: nome, kind: 'object', category: 'Fantasy', enabled: true)
    a.image.attach(io: StringIO.new('arte'), filename: "ink-#{nome}.png", content_type: 'image/png')
    a.save!
    a
  end

  before { Rails.cache.clear }

  it 'o corpo é JSON de verdade, não uma string aspada' do
    # ⚠️ `render json:` numa String já-JSON devolveria o payload inteiro como
    # um literal aspado — o front receberia texto em vez do objeto.
    cria_asset('Arvore')
    get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include('application/json')
    corpo = JSON.parse(response.body)
    expect(corpo['map_assets']).to be_an(Array)
    expect(corpo['map_assets'].first['name']).to eq('Arvore')
  end

  it 'a 2ª chamada com o mesmo ETag responde 304 (não re-baixa os 6,84 MB)' do
    cria_asset('Pedra')
    get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)
    etag = response.headers['ETag']
    expect(etag).to be_present

    get '/api/v1/admin/map_assets',
        headers: bearer_headers_for(dm).merge('HTTP_IF_NONE_MATCH' => etag)
    expect(response).to have_http_status(:not_modified)
  end

  it '⚠️ anexar imagem invalida a lista, mesmo sem tocar em updated_at' do
    a = cria_asset('Tocha')
    get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)
    etag_antes = response.headers['ETag']

    # foi exatamente este o caso das 17.317 miniaturas: o anexo entra e o
    # `updated_at` do registo fica igual. Sem o id do anexo na versão, a
    # biblioteca serviria para sempre a lista SEM thumbUrl.
    a.thumb.attach(io: StringIO.new('mini'), filename: 'ink-Tocha.webp', content_type: 'image/webp')

    get '/api/v1/admin/map_assets', headers: bearer_headers_for(dm)
    expect(response.headers['ETag']).not_to eq(etag_antes)
    registo = JSON.parse(response.body)['map_assets'].find { |r| r['id'] == a.id }
    expect(registo['thumbUrl']).to be_present
  end

  it 'filtros diferentes não partilham a entrada do cache' do
    cria_asset('Objeto')
    tex = MapAsset.new(name: 'Textura', kind: 'texture', category: 'Chao', enabled: true)
    tex.image.attach(io: StringIO.new('t'), filename: 'inktex-1.png', content_type: 'image/png')
    tex.save!

    get '/api/v1/admin/map_assets?kind=object', headers: bearer_headers_for(dm)
    objetos = JSON.parse(response.body)['map_assets'].map { |r| r['name'] }
    get '/api/v1/admin/map_assets?kind=texture', headers: bearer_headers_for(dm)
    texturas = JSON.parse(response.body)['map_assets'].map { |r| r['name'] }

    expect(objetos).to include('Objeto')
    expect(objetos).not_to include('Textura')
    expect(texturas).to eq(['Textura'])
  end
end
