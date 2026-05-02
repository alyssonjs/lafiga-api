# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AuthenticationController', type: :request do
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player', permissions: []) }
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin', permissions: %w[manage_users]) }

  describe 'POST /authenticate (login)' do
    let!(:user) do
      create(:user, role: player_role, password: 'secret123', password_confirmation: 'secret123')
    end

    it 'retorna token + user_infos + role + permissions com credenciais válidas' do
      post '/authenticate', params: { email: user.email, password: 'secret123' }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body['token']).to be_present
      expect(body['user_infos']['id']).to eq(user.id)
      expect(body['user_infos']['email']).to eq(user.email)
      expect(body['role']).to eq('player')
      expect(body['permissions']).to eq([])
    end

    it 'NÃO inclui password_digest no payload (regressão guard — PR C)' do
      # Bug pré-existente até PR C: `user_infos: @user` passava o `User`
      # ActiveRecord direto pelo `to_json`, vazando `password_digest`
      # (bcrypt hash). Filtrado via `User::SENSITIVE_API_FIELDS`.
      post '/authenticate', params: { email: user.email, password: 'secret123' }

      body = response.parsed_body
      expect(body['user_infos'].keys).not_to include('password_digest')
      expect(body['user_infos'].keys).not_to include('password')
    end

    it 'retorna 401 com senha errada' do
      post '/authenticate', params: { email: user.email, password: 'wrong-password' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna 401 com email inexistente' do
      post '/authenticate', params: { email: 'nope@nope.test', password: 'secret123' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'normaliza role canônico do DB para "player" no payload' do
      post '/authenticate', params: { email: user.email, password: 'secret123' }
      expect(response.parsed_body['role']).to eq('player')
    end

    it 'serializa Admin como "dm" (alias legado consumido pelo front)' do
      admin = create(:user, role: admin_role, password: 'secret123', password_confirmation: 'secret123')
      post '/authenticate', params: { email: admin.email, password: 'secret123' }
      expect(response.parsed_body['role']).to eq('dm')
    end
  end

  describe 'POST /auth/signup' do
    it 'cria user + retorna token sem vazar password_digest (regressão guard)' do
      role = player_role
      payload = {
        name: 'Aria',
        username: "aria_#{SecureRandom.hex(4)}",
        email: "aria_#{SecureRandom.hex(4)}@lafiga.test",
        password: 'secret123',
        password_confirmation: 'secret123',
        role_id: role.id
      }

      post '/auth/signup', params: payload

      expect(response).to have_http_status(:created)
      body = response.parsed_body

      expect(body['token']).to be_present
      expect(body['user_infos']['email']).to eq(payload[:email])
      expect(body['user_infos'].keys).not_to include('password_digest')
      expect(body['user_infos'].keys).not_to include('password')
      expect(body['role']).to eq('player')
    end

    it 'retorna 422 com payload inválido' do
      post '/auth/signup', params: { email: 'malformed', password: 'x' }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
