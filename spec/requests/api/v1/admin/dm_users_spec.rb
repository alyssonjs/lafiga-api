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

  describe 'POST /api/v1/admin/dm_users' do
    it 'bloqueia jogador comum (403)' do
      post '/api/v1/admin/dm_users',
           params: { user: { email: 'x@test.com', username: 'xuser' } }.to_json,
           headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'cria utilizador com senha password' do
      email = "created_#{SecureRandom.hex(4)}@lafiga.test"
      username = "createduser_#{SecureRandom.hex(4)}"
      post '/api/v1/admin/dm_users',
           params: { user: { name: 'Novo Jogador', email: email, username: username } }.to_json,
           headers: dm_headers
      expect(response).to have_http_status(:created)
      u = response.parsed_body['user']
      expect(u['email']).to eq(email)
      expect(u['name']).to eq('Novo Jogador')
      expect(u['username']).to eq(username)
      expect(u['role']['name']).to be_in(%w[Player User])
      created = User.find_by(email: email)
      expect(created).to be_present
      expect(created.authenticate('password')).to eq(created)
    end

    it 'ignora DM_PASSWORD_RESET_DEFAULT: senha continua password' do
      prev = ENV['DM_PASSWORD_RESET_DEFAULT']
      ENV['DM_PASSWORD_RESET_DEFAULT'] = 'ShouldNotBeUsed'
      email = "envpwd_#{SecureRandom.hex(4)}@lafiga.test"
      post '/api/v1/admin/dm_users',
           params: { user: { email: email, username: "u_#{SecureRandom.hex(4)}" } }.to_json,
           headers: dm_headers
      expect(response).to have_http_status(:created)
      expect(User.find_by!(email: email).authenticate('password')).to be_truthy
      expect(User.find_by!(email: email).authenticate('ShouldNotBeUsed')).to be_falsy
    ensure
      if prev
        ENV['DM_PASSWORD_RESET_DEFAULT'] = prev
      else
        ENV.delete('DM_PASSWORD_RESET_DEFAULT')
      end
    end

    it 'normaliza @ no início do username' do
      email = "at_#{SecureRandom.hex(4)}@lafiga.test"
      raw = "u_#{SecureRandom.hex(3)}"
      post '/api/v1/admin/dm_users',
           params: { user: { email: email, username: "@#{raw}" } }.to_json,
           headers: dm_headers
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['user']['username']).to eq(raw)
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
    it 'redefine a senha para password (sempre)' do
      post "/api/v1/admin/dm_users/#{player.id}/reset_password", headers: dm_headers
      expect(response).to have_http_status(:no_content)
      expect(player.reload.authenticate('password')).to eq(player)
    end

    it 'ignora DM_PASSWORD_RESET_DEFAULT: fica password' do
      prev = ENV['DM_PASSWORD_RESET_DEFAULT']
      ENV['DM_PASSWORD_RESET_DEFAULT'] = 'NotUsedByReset'
      post "/api/v1/admin/dm_users/#{player.id}/reset_password", headers: dm_headers
      expect(response).to have_http_status(:no_content)
      reloaded = player.reload
      expect(reloaded.authenticate('password')).to eq(reloaded)
      expect(reloaded.authenticate('NotUsedByReset')).to be_falsy
    ensure
      if prev
        ENV['DM_PASSWORD_RESET_DEFAULT'] = prev
      else
        ENV.delete('DM_PASSWORD_RESET_DEFAULT')
      end
    end
  end
end
