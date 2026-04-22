# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::DmUserPickerController', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let!(:dm_user) { create(:user, role: dm_role, name: 'DM Site', username: "dm_site_#{SecureRandom.hex(4)}") }
  let!(:player) { create(:user, role: player_role, name: 'ZaraPickerXy', username: "zara_pick_#{SecureRandom.hex(4)}") }
  let(:dm_headers) { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player) }

  describe 'GET /api/v1/admin/dm_user_picker' do
    it 'bloqueia jogador comum (403)' do
      get '/api/v1/admin/dm_user_picker', headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'permite DM e devolve lista resumida (campos id, name, username, email)' do
      get '/api/v1/admin/dm_user_picker', params: { q: player.username }, headers: dm_headers
      expect(response).to have_http_status(:ok)
      users = response.parsed_body['users']
      expect(users).to be_an(Array)
      expect(users.map { |u| u['id'] }).to include(player.id)
      sample = users.find { |u| u['id'] == player.id }
      expect(sample.keys).to include('id', 'name', 'username', 'email')
    end

    it 'filtra por q (nome ou username)' do
      get '/api/v1/admin/dm_user_picker', params: { q: 'ZaraPickerXy' }, headers: dm_headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['users'].map { |u| u['id'] }
      expect(ids).to eq([player.id])
    end
  end
end
