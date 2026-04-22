# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Monsters', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
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
    it 'requires admin' do
      get '/api/v1/admin/monsters', headers: bearer_headers_for(player)
      expect(response).to have_http_status(:unauthorized)
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

    it 'rejeita 401 para player' do
      post '/api/v1/admin/monsters',
           params: { monster: { name: 'Hijack' } }.to_json,
           headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:unauthorized)
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
