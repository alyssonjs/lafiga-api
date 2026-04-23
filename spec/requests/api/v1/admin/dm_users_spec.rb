# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::DmUsersController', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let!(:dm_user) { create(:user, role: dm_role, name: 'DM Site', username: "dm_users_dm_#{SecureRandom.hex(4)}") }
  let!(:player) do
    create(
      :user,
      role: player_role,
      name: 'AliceUsers',
      username: "alice_users_#{SecureRandom.hex(4)}",
      email: "alice_users_#{SecureRandom.hex(4)}@lafiga.test"
    )
  end
  let(:dm_headers) { bearer_headers_for(dm_user).merge('Content-Type' => 'application/json') }
  let(:player_headers) { bearer_headers_for(player).merge('Content-Type' => 'application/json') }

  describe 'GET /api/v1/admin/dm_users' do
    it 'bloqueia jogador comum (403)' do
      get '/api/v1/admin/dm_users', headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'permite DM e devolve lista com characters_count' do
      get '/api/v1/admin/dm_users', params: { q: player.email }, headers: dm_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['users']).to be_an(Array)
      row = body['users'].find { |u| u['id'] == player.id }
      expect(row).to include('id', 'name', 'username', 'email', 'role', 'characters_count')
      expect(body['meta']).to include('page', 'per_page', 'total')
    end
  end

  describe 'GET /api/v1/admin/dm_users/:id' do
    it 'inclui personagens resumidas' do
      get "/api/v1/admin/dm_users/#{player.id}", headers: dm_headers
      expect(response).to have_http_status(:ok)
      u = response.parsed_body['user']
      expect(u['characters']).to be_an(Array)
    end
  end

  describe 'PATCH /api/v1/admin/dm_users/:id' do
    it 'atualiza nome e email' do
      new_email = "patched_#{SecureRandom.hex(4)}@lafiga.test"
      patch "/api/v1/admin/dm_users/#{player.id}",
            params: { user: { name: 'Alice Patched', email: new_email } }.to_json,
            headers: dm_headers
      expect(response).to have_http_status(:ok)
      u = response.parsed_body['user']
      expect(u['name']).to eq('Alice Patched')
      expect(u['email']).to eq(new_email)
      expect(player.reload.email).to eq(new_email)
    end
  end

  describe 'POST /api/v1/admin/dm_users/:id/reset_password' do
    it '422 quando ENV não definido' do
      prev = ENV['DM_PASSWORD_RESET_DEFAULT']
      ENV.delete('DM_PASSWORD_RESET_DEFAULT')
      post "/api/v1/admin/dm_users/#{player.id}/reset_password", headers: dm_headers
      expect(response).to have_http_status(:unprocessable_entity)
    ensure
      ENV['DM_PASSWORD_RESET_DEFAULT'] = prev if prev
    end

    it 'define senha quando ENV presente' do
      prev = ENV['DM_PASSWORD_RESET_DEFAULT']
      ENV['DM_PASSWORD_RESET_DEFAULT'] = 'NewDefaultPwd99'
      post "/api/v1/admin/dm_users/#{player.id}/reset_password", headers: dm_headers
      expect(response).to have_http_status(:no_content)
      expect(player.reload.authenticate('NewDefaultPwd99')).to eq(player)
    ensure
      if prev
        ENV['DM_PASSWORD_RESET_DEFAULT'] = prev
      else
        ENV.delete('DM_PASSWORD_RESET_DEFAULT')
      end
    end
  end
end
