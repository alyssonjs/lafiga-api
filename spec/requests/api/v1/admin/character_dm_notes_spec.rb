# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::CharacterDmNotesController', type: :request do
  let(:admin_role) { Role.find_by(name: 'Admin') || create(:role, name: 'Admin') }
  let(:dm_role)    { Role.find_by(name: 'DM')    || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }

  let(:admin_user) { create(:user, role: admin_role, name: 'Admin') }
  let(:dm_user)    { create(:user, role: dm_role, name: 'Mestre') }
  let(:player_user) { create(:user, role: player_role, name: 'Alice') }

  let(:admin_headers) { bearer_headers_for(admin_user) }
  let(:dm_headers)    { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player_user) }

  let!(:pc) { create(:character, user: player_user, name: 'Hero', background: 'Test') }

  describe 'GET /api/v1/admin/characters/:character_id/dm_notes' do
    it 'retorna vazio para mestre (DM)' do
      get "/api/v1/admin/characters/#{pc.id}/dm_notes", headers: dm_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['dm_notes']).to eq('')
    end

    it 'retorna texto persistido para Admin' do
      pc.update_column(:dm_notes, 'Segredo do plot')
      get "/api/v1/admin/characters/#{pc.id}/dm_notes", headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['dm_notes']).to eq('Segredo do plot')
    end

    it 'bloqueia jogador' do
      get "/api/v1/admin/characters/#{pc.id}/dm_notes", headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PUT /api/v1/admin/characters/:character_id/dm_notes' do
    it 'atualiza para DM' do
      put "/api/v1/admin/characters/#{pc.id}/dm_notes",
          params: { dm_notes: 'Lembrete: aliado infiltrado' },
          headers: dm_headers
      expect(response).to have_http_status(:ok)
      expect(pc.reload.dm_notes).to eq('Lembrete: aliado infiltrado')
    end

    it 'bloqueia jogador' do
      put "/api/v1/admin/characters/#{pc.id}/dm_notes",
          params: { dm_notes: 'hack' },
          headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
