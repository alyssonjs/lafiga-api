# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Monsters', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:dm_role)     { Role.find_by(name: 'DM')     || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:dm)          { create(:user, role: dm_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }

  let!(:goblin) do
    Monster.create!(
      slug: 'mon-goblin',
      name: 'Goblin',
      name_en: 'Goblin',
      source: 'srd',
      payload: {
        'id' => 'mon-goblin',
        'name' => 'Goblin',
        'nameEN' => 'Goblin',
        'size' => 'Pequeno',
        'type' => 'Humanoide',
        'cr' => '1/4',
        'xp' => 50,
        'ac' => 15,
        'hp' => 7,
        'stats' => { 'str' => 8, 'dex' => 14, 'con' => 10, 'int' => 10, 'wis' => 8, 'cha' => 8 },
        'actions' => [
          { 'name' => 'Cimitarra', 'description' => 'Ataque CaC com Arma: +4 para acertar' }
        ]
      }
    )
  end

  describe 'GET /api/v1/admin/monsters' do
    it 'sem token retorna 401' do
      get '/api/v1/admin/monsters'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'jogador comum retorna 403 (DM/Admin only — nao desloga)' do
      get '/api/v1/admin/monsters', headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end

    it 'lista monstros com payload completo' do
      get '/api/v1/admin/monsters', headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      row  = body['monsters'].find { |m| m['id'] == 'mon-goblin' }
      expect(row).to be_present
      expect(row['name']).to eq('Goblin')
      expect(row['cr']).to eq('1/4')
      expect(row['actions'].first['name']).to eq('Cimitarra')
    end

    it 'filtra por type e cr_max' do
      Monster.create!(slug: 'mon-dragon', name: 'Dragao', source: 'srd',
                      payload: { 'type' => 'Dragao', 'cr' => '17', 'xp' => 18000 })

      get '/api/v1/admin/monsters', params: { type: 'Humanoide', cr_max: 1 }, headers: headers
      slugs = response.parsed_body['monsters'].map { |m| m['id'] }
      expect(slugs).to include('mon-goblin')
      expect(slugs).not_to include('mon-dragon')
    end
  end

  describe 'POST /api/v1/admin/monsters' do
    it 'cria monstro homebrew com payload rico' do
      payload = {
        monster: {
          name: 'Bicho de Teste',
          source: 'homebrew',
          payload: {
            type: 'Besta', size: 'Medio', cr: '1', xp: 200, ac: 12, hp: 19,
            stats: { str: 14, dex: 12, con: 12, int: 2, wis: 10, cha: 5 },
            actions: [{ name: 'Mordida', description: 'CaC: +4, 1d6+2 perfurante.' }]
          }
        }
      }
      expect {
        post '/api/v1/admin/monsters', params: payload.to_json, headers: headers
      }.to change(Monster, :count).by(1)
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig('monster', 'name')).to eq('Bicho de Teste')
      expect(body.dig('monster', 'cr')).to eq('1')
    end

    it 'rejeita payload sem name' do
      post '/api/v1/admin/monsters', params: { monster: { source: 'homebrew' } }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejeita jogador comum com 403 (nao desloga)' do
      post '/api/v1/admin/monsters',
           params: { monster: { name: 'Hijack' } }.to_json,
           headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/monsters/:id' do
    it 'atualiza por slug' do
      patch "/api/v1/admin/monsters/#{goblin.slug}",
            params: { monster: { payload: { hp: 12 } } }.to_json,
            headers: headers
      expect(response).to have_http_status(:ok)
      expect(goblin.reload.payload['hp']).to eq(12)
    end

    # O ponto do fix: DM (nao-Admin) pode salvar, como em magic_items/spells.
    it 'permite o DM (nao-Admin) salvar' do
      patch "/api/v1/admin/monsters/#{goblin.slug}",
            params: { monster: { payload: { hp: 20 } } }.to_json,
            headers: bearer_headers_for(dm).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:ok)
      expect(goblin.reload.payload['hp']).to eq(20)
    end
  end

  describe 'DELETE /api/v1/admin/monsters/:id' do
    it 'remove' do
      expect {
        delete "/api/v1/admin/monsters/#{goblin.slug}", headers: headers
      }.to change(Monster, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /api/v1/admin/monsters/bulk_import' do
    it 'aceita Array de entradas (formato dump do front)' do
      payload = {
        monsters: [
          { id: 'mon-novo-1', name: 'Novo Um', type: 'Aberracao', cr: '5', xp: 1800 },
          { id: 'mon-novo-2', name: 'Novo Dois', type: 'Constructo', cr: '2', xp: 450 }
        ]
      }
      expect {
        post '/api/v1/admin/monsters/bulk_import', params: payload.to_json, headers: headers
      }.to change(Monster, :count).by(2)
      body = response.parsed_body
      expect(body['upserted']).to eq(2)
    end

    it 'dry_run nao persiste' do
      payload = { monsters: [{ id: 'mon-dryrun', name: 'X' }], dry_run: 'true' }
      expect {
        post '/api/v1/admin/monsters/bulk_import', params: payload.to_json, headers: headers
      }.not_to change(Monster, :count)
      expect(response.parsed_body['dry_run']).to be true
    end
  end
end

RSpec.describe 'Token do monstro (biblioteca de objetos)', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }

  let!(:asset) do
    a = MapAsset.new(name: 'Lobo do mapa', kind: 'object', category: 'Meus', user: dm)
    a.image.attach(
      io: StringIO.new(Base64.decode64(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
      )),
      filename: 'token.png', content_type: 'image/png'
    )
    a.save!
    a
  end

  let!(:lobo) do
    Monster.create!(slug: 'mon-lobo', name: 'Lobo', source: 'srd',
                    payload: { 'ac' => 13, 'hp' => 11, 'cr' => '1/4' })
  end

  it 'grava a referencia e devolve a URL no payload que o front consome' do
    patch "/api/v1/admin/monsters/#{lobo.slug}",
          params: { monster: { name: 'Lobo', token_map_asset_id: asset.id } }.to_json,
          headers: headers

    expect(response).to have_http_status(:ok)
    expect(lobo.reload.token_map_asset_id).to eq(asset.id)

    corpo = response.parsed_body['monster']
    expect(corpo['tokenMapAssetId']).to eq(asset.id)
    expect(corpo['tokenImageUrl']).to eq("/api/v1/admin/map_assets/#{asset.id}/image?v=#{asset.id}")
  end

  # ⚠️ O token e COLUNA, nao statblock: o re-import do Open5e reescreve o
  # `payload` inteiro e apagaria a escolha do Mestre se ele vivesse la.
  it 'reescrever o payload NAO apaga o token' do
    lobo.update!(token_map_asset_id: asset.id)

    patch "/api/v1/admin/monsters/#{lobo.slug}",
          params: { monster: { name: 'Lobo', payload: { 'ac' => 14, 'hp' => 12 } } }.to_json,
          headers: headers

    expect(response).to have_http_status(:ok)
    lobo.reload
    expect(lobo.token_map_asset_id).to eq(asset.id)
    expect(lobo.payload['ac']).to eq(14)
    # E nao vaza para dentro do statblock.
    expect(lobo.payload).not_to have_key('tokenMapAssetId')
  end

  it 'monstro sem token nao ganha as chaves' do
    get '/api/v1/admin/monsters', headers: bearer_headers_for(dm)

    linha = response.parsed_body['monsters'].find { |m| m['id'] == 'mon-lobo' }
    expect(linha).not_to have_key('tokenImageUrl')
  end

  it 'o publico tambem recebe o token — o desenho e da mesa inteira' do
    lobo.update!(token_map_asset_id: asset.id)

    get '/api/v1/public/monsters'
    linha = response.parsed_body['monsters'].find { |m| m['id'] == 'mon-lobo' }
    expect(linha['tokenImageUrl']).to include("map_assets/#{asset.id}/image")
  end
end
