# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Feats', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }

  let!(:tough_feat) do
    Feat.create!(
      api_index: 'tough',
      name: 'Resistente',
      description: 'Seus pontos de vida maximos aumentam em uma quantia igual a duas vezes seu nivel.',
      ability_bonuses: {}.to_json,
      special_rules: { 'hp_per_level' => 2 }.to_json
    )
  end

  describe 'GET /api/v1/admin/feats' do
    it 'requires admin' do
      get '/api/v1/admin/feats', headers: bearer_headers_for(player)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lista feats com payload no mesmo shape do public/feats' do
      get '/api/v1/admin/feats', headers: headers
      expect(response).to have_http_status(:ok)
      row = response.parsed_body['feats'].find { |f| f['api_index'] == 'tough' }
      expect(row).to be_present
      expect(row['name']).to eq('Resistente')
      expect(row['special_rules']['hp_per_level']).to eq(2)
    end

    it 'busca por nome (q)' do
      Feat.create!(api_index: 'lucky', name: 'Sortudo', description: 'X')
      get '/api/v1/admin/feats', params: { q: 'sort' }, headers: headers
      names = response.parsed_body['feats'].map { |f| f['name'] }
      expect(names).to include('Sortudo')
      expect(names).not_to include('Resistente')
    end
  end

  describe 'POST /api/v1/admin/feats' do
    it 'cria feat e deriva api_index quando omitido' do
      payload = {
        feat: {
          name: 'Talento Novo',
          description: 'Descricao do talento.',
          ability_bonuses: { 'str' => 1 },
          special_rules: { 'movement_bonus' => 3 }
        }
      }
      expect {
        post '/api/v1/admin/feats', params: payload.to_json, headers: headers
      }.to change(Feat, :count).by(1)
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig('feat', 'api_index')).to eq('pt-talento-novo')
      expect(body.dig('feat', 'ability_bonuses', 'str')).to eq(1)
    end

    it 'rejeita payload sem name' do
      post '/api/v1/admin/feats', params: { feat: { description: 'x' } }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'bloqueia 401 para player' do
      post '/api/v1/admin/feats',
           params: { feat: { name: 'Hijack' } }.to_json,
           headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/admin/feats/:id' do
    it 'atualiza por api_index' do
      patch "/api/v1/admin/feats/#{tough_feat.api_index}",
            params: { feat: { description: 'novo body' } }.to_json,
            headers: headers
      expect(response).to have_http_status(:ok)
      expect(tough_feat.reload.description).to eq('novo body')
    end

    it 'atualiza JSON fields aceitando Hash' do
      patch "/api/v1/admin/feats/#{tough_feat.api_index}",
            params: { feat: { special_rules: { 'hp_per_level' => 3 } } }.to_json,
            headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(tough_feat.reload.special_rules)).to eq('hp_per_level' => 3)
    end
  end

  describe 'DELETE /api/v1/admin/feats/:id' do
    it 'deleta quando nao ha SheetFeat' do
      expect {
        delete "/api/v1/admin/feats/#{tough_feat.api_index}", headers: headers
      }.to change(Feat, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
