# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::MeController', type: :request do
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player', permissions: []) }
  let(:dm_role)     { Role.find_by(name: 'DM')     || create(:role, name: 'DM', permissions: %w[manage_sessions]) }
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin', permissions: %w[manage_users manage_sessions]) }

  let(:player) { create(:user, role: player_role) }
  let(:dm)     { create(:user, role: dm_role) }
  let(:admin)  { create(:user, role: admin_role) }

  describe 'GET /api/v1/me' do
    context 'sem token' do
      it 'retorna 401' do
        get '/api/v1/me'
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'com token JWT inválido' do
      it 'retorna 401' do
        get '/api/v1/me', headers: { 'Authorization' => 'Bearer not-a-real-token' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'Player autenticado' do
      it 'retorna user_infos + role normalizado para "player" + permissions' do
        get '/api/v1/me', headers: bearer_headers_for(player)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body

        expect(body['user_infos']['id']).to eq(player.id)
        expect(body['user_infos']['email']).to eq(player.email)
        expect(body['role']).to eq('player')
        expect(body['permissions']).to eq([])
      end

      it 'NÃO inclui o password_digest no payload' do
        get '/api/v1/me', headers: bearer_headers_for(player)
        body = response.parsed_body
        expect(body['user_infos'].keys).not_to include('password_digest', 'password')
      end
    end

    context 'DM autenticado' do
      it 'retorna role "dm" + permissions populadas' do
        get '/api/v1/me', headers: bearer_headers_for(dm)

        body = response.parsed_body
        expect(body['role']).to eq('dm')
        expect(body['permissions']).to include('manage_sessions')
      end
    end

    context 'Admin autenticado' do
      it 'retorna role "dm" (alias legado: Admin → dm no contrato do front)' do
        get '/api/v1/me', headers: bearer_headers_for(admin)

        body = response.parsed_body
        expect(body['role']).to eq('dm')
        expect(body['permissions']).to include('manage_users', 'manage_sessions')
      end
    end

    context 'role mudou no DB depois de o token ser emitido' do
      # Cenário do bug que motivou este endpoint: front confiava em
      # `localStorage['role']` (cacheado do payload de login), então não
      # detectava promoção/rebaixamento até o usuário re-logar. Aqui
      # garantimos que /me sempre reflete o estado autoritativo do DB.
      it 'reflete o role atual quando o usuário foi promovido a DM' do
        headers = bearer_headers_for(player)
        player.update!(role: dm_role)

        get '/api/v1/me', headers: headers
        expect(response.parsed_body['role']).to eq('dm')
      end

      it 'reflete o role atual quando o usuário foi rebaixado de DM para Player' do
        headers = bearer_headers_for(dm)
        dm.update!(role: player_role)

        get '/api/v1/me', headers: headers
        expect(response.parsed_body['role']).to eq('player')
      end
    end

    context 'header com role/permissions falsificados pelo cliente' do
      # Ataque que motivou o PR: usuário tenta sobrescrever role via
      # `localStorage` (que vira parte de algumas requests headers ou body).
      # O backend ignora qualquer pista de role enviada pelo cliente:
      # JWT só carrega `user_id`, e o role é re-buscado do DB.
      it 'ignora cabeçalho X-Role tentando promover Player a DM' do
        get '/api/v1/me',
            headers: bearer_headers_for(player).merge(
              'X-Role' => 'dm',
              'X-Permissions' => 'manage_users'
            )

        body = response.parsed_body
        expect(body['role']).to eq('player')
        expect(body['permissions']).to eq([])
      end
    end
  end

  describe 'PATCH /api/v1/me/ui_preferences' do
    it 'persiste as fichas fixadas do mestre por sessão e as devolve após reload' do
      patch '/api/v1/me/ui_preferences',
            params: {
              floating_sheet_pins: {
                session_id: 'schedule-42',
                character_ids: %w[12 18 12]
              }
            },
            headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig(
        'user_infos', 'ui_preferences', 'floating_sheet_pins_by_session', 'schedule-42'
      )).to eq(%w[12 18])

      get '/api/v1/me', headers: bearer_headers_for(dm)
      expect(response.parsed_body.dig(
        'user_infos', 'ui_preferences', 'floating_sheet_pins_by_session', 'schedule-42'
      )).to eq(%w[12 18])
    end

    it 'preserva os atalhos de outras sessões ao atualizar a sessão atual' do
      dm.update!(ui_preferences: {
        'combat_hotbar' => true,
        'floating_sheet_pins_by_session' => { 'schedule-1' => ['7'] }
      })

      patch '/api/v1/me/ui_preferences',
            params: {
              floating_sheet_pins: {
                session_id: 'schedule-2',
                character_ids: ['9']
              }
            },
            headers: bearer_headers_for(dm)

      preferences = response.parsed_body.dig('user_infos', 'ui_preferences')
      expect(preferences['combat_hotbar']).to be(true)
      expect(preferences['floating_sheet_pins_by_session']).to eq(
        'schedule-1' => ['7'],
        'schedule-2' => ['9']
      )
    end

    it 'remove a preferência da sessão quando todas as fichas são desfixadas' do
      dm.update!(ui_preferences: {
        'floating_sheet_pins_by_session' => {
          'schedule-1' => ['7'],
          'schedule-2' => ['9']
        }
      })

      patch '/api/v1/me/ui_preferences',
            params: {
              floating_sheet_pins: {
                session_id: 'schedule-1',
                character_ids: []
              }
            },
            headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig(
        'user_infos', 'ui_preferences', 'floating_sheet_pins_by_session'
      )).to eq('schedule-2' => ['9'])
    end

    it 'impede que jogador grave atalhos exclusivos do mestre' do
      patch '/api/v1/me/ui_preferences',
            params: {
              floating_sheet_pins: {
                session_id: 'schedule-42',
                character_ids: ['12']
              }
            },
            headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
      expect(player.reload.ui_preferences || {}).not_to have_key('floating_sheet_pins_by_session')
    end
  end
end
