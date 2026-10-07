# frozen_string_literal: true

require 'rails_helper'

# Atribuir PAPEL na tela de Utilizadores (07/10/2026).
#
# Era o buraco que sobrava do papel Editor: dava para criar o papel, mas não
# havia por onde dá-lo a alguém sem abrir um console no servidor.
RSpec.describe 'Admin::DmUsers — papel', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM')     || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:editor_role) { Role.find_by(name: 'Editor') || create(:role, name: 'Editor') }

  let(:dm)     { create(:user, role: dm_role) }
  let(:outro)  { create(:user, role: player_role) }
  let(:player) { create(:user, role: player_role) }

  describe 'GET /api/v1/admin/dm_users/roles' do
    before { dm_role; player_role; editor_role }

    it 'lista os papéis atribuíveis, em ordem e com explicação' do
      get '/api/v1/admin/dm_users/roles', headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      papeis = response.parsed_body['roles']
      expect(papeis.map { |r| r['name'] }).to eq(%w[DM Editor Player])
      expect(papeis.find { |r| r['name'] == 'Editor' }['description']).to include('Redige a wiki')
    end

    it '⚠️ não oferece os LEGADOS — ninguém volta a distribuir Guest nem Admin' do
      Role.find_or_create_by!(name: 'Guest') { |r| r.permissions = [] }
      Role.find_or_create_by!(name: 'Admin') { |r| r.permissions = [] }

      get '/api/v1/admin/dm_users/roles', headers: bearer_headers_for(dm)

      expect(response.parsed_body['roles'].map { |r| r['name'] }).not_to include('Guest', 'Admin')
    end

    it 'jogador comum recebe 403' do
      get '/api/v1/admin/dm_users/roles', headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/dm_users/:id' do
    it 'o Mestre promove alguém a Editor — é a feature' do
      patch "/api/v1/admin/dm_users/#{outro.id}", params: { user: { role_id: editor_role.id } },
            as: :json, headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      expect(outro.reload.role.name).to eq('Editor')
      expect(outro.may_edit_content?).to be(true)
      # E continua sem ser Mestre: redige texto e nada mais.
      expect(Group.user_is_dm?(outro.reload)).to be(false)
    end

    it 'e desfaz, devolvendo a jogador' do
      outro.update!(role: editor_role)

      patch "/api/v1/admin/dm_users/#{outro.id}", params: { user: { role_id: player_role.id } },
            as: :json, headers: bearer_headers_for(dm)

      expect(outro.reload.role.name).to eq('Player')
      expect(outro.may_edit_content?).to be(false)
    end

    it '⚠️ o Mestre NÃO muda o próprio papel — rebaixar-se trancava-o fora da tela' do
      patch "/api/v1/admin/dm_users/#{dm.id}", params: { user: { role_id: player_role.id } },
            as: :json, headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('seu próprio papel')
      expect(dm.reload.role.name).to eq('DM')
    end

    it 'recusa papel fora da lista branca' do
      guest = Role.find_or_create_by!(name: 'Guest') { |r| r.permissions = [] }

      patch "/api/v1/admin/dm_users/#{outro.id}", params: { user: { role_id: guest.id } },
            as: :json, headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(outro.reload.role.name).to eq('Player')
    end

    it 'editar nome sem mandar papel não mexe no papel' do
      patch "/api/v1/admin/dm_users/#{outro.id}", params: { user: { name: 'Nome Novo' } },
            as: :json, headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      expect(outro.reload.name).to eq('Nome Novo')
      expect(outro.role.name).to eq('Player')
    end

    it '⚠️ o EDITOR não promove ninguém — a tela é do Mestre' do
      editor = create(:user, role: editor_role)

      patch "/api/v1/admin/dm_users/#{outro.id}", params: { user: { role_id: editor_role.id } },
            as: :json, headers: bearer_headers_for(editor)

      expect(response).to have_http_status(:forbidden)
      expect(outro.reload.role.name).to eq('Player')
    end

    it 'jogador comum recebe 403' do
      patch "/api/v1/admin/dm_users/#{outro.id}", params: { user: { role_id: editor_role.id } },
            as: :json, headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
