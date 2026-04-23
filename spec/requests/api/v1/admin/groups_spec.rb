# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::GroupsController', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:other_user)  { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }

  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm_user) { create(:user, role: dm_role) }

  describe 'GET /api/v1/admin/groups' do
    it 'lista todos os grupos para o mestre site-wide (DM)' do
      g1 = create(:group, name: 'A')
      g2 = create(:group, name: 'B', dm_user_id: other_user.id)

      get '/api/v1/admin/groups', headers: bearer_headers_for(dm_user)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['groups'].map { |x| x['id'] }
      expect(ids).to contain_exactly(g1.id, g2.id)
    end

    it 'rejeita jogador comum' do
      get '/api/v1/admin/groups', headers: bearer_headers_for(player)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/admin/groups/:id/add_character' do
    it 'rejeita jogador comum (nao e mestre site-wide)' do
      group     = create(:group, name: 'X')
      character = create(:character, user: player)

      post "/api/v1/admin/groups/#{group.id}/add_character",
           params: { character_id: character.id },
           headers: bearer_headers_for(player), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'permite ao mestre (DM) vincular character de outro usuario ao grupo' do
      group     = create(:group, name: 'Mesa DM')
      character = create(:character, user: other_user)

      post "/api/v1/admin/groups/#{group.id}/add_character",
           params: { character_id: character.id },
           headers: bearer_headers_for(dm_user), as: :json

      expect(response).to have_http_status(:ok)
      expect(character.reload.group_id).to eq(group.id)
    end

    it 'permite ao admin vincular character de outro usuario ao grupo' do
      group     = create(:group, name: 'Mesa do DM')
      character = create(:character, user: other_user)

      expect(character.group_id).to be_nil

      post "/api/v1/admin/groups/#{group.id}/add_character",
           params: { character_id: character.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(character.reload.group_id).to eq(group.id)
      member_ids = response.parsed_body['group']['members'].map { |m| m['id'] }
      expect(member_ids).to include(character.id)
    end

    it 'idempotente quando o character ja esta no grupo' do
      group     = create(:group, name: 'Mesa')
      character = create(:character, user: other_user, group: group)

      post "/api/v1/admin/groups/#{group.id}/add_character",
           params: { character_id: character.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['unchanged']).to eq(true)
    end

    it 'retorna 404 para character inexistente' do
      group = create(:group, name: 'Mesa')

      post "/api/v1/admin/groups/#{group.id}/add_character",
           params: { character_id: 999_999 },
           headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'retorna 404 para grupo inexistente' do
      character = create(:character, user: other_user)

      post "/api/v1/admin/groups/999999/add_character",
           params: { character_id: character.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'move character de um grupo para outro' do
      origin_group = create(:group, name: 'Origem')
      target_group = create(:group, name: 'Destino')
      character    = create(:character, user: other_user, group: origin_group)

      post "/api/v1/admin/groups/#{target_group.id}/add_character",
           params: { character_id: character.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(character.reload.group_id).to eq(target_group.id)
    end
  end

  describe 'POST /api/v1/admin/groups/:id/remove_character' do
    it 'permite ao admin desvincular character de qualquer usuario' do
      group     = create(:group, name: 'Mesa')
      character = create(:character, user: other_user, group: group)

      post "/api/v1/admin/groups/#{group.id}/remove_character",
           params: { character_id: character.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(character.reload.group_id).to be_nil
    end

    it 'idempotente quando o character ja nao esta no grupo' do
      group     = create(:group, name: 'Mesa')
      character = create(:character, user: other_user)

      post "/api/v1/admin/groups/#{group.id}/remove_character",
           params: { character_id: character.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['unchanged']).to eq(true)
    end
  end

  describe 'DELETE /api/v1/admin/groups/:id' do
    it 'apaga grupo mesmo com personagens vinculados (group_id vira null)' do
      group     = create(:group, name: 'Com PCs')
      character = create(:character, user: other_user, group: group)

      expect {
        delete "/api/v1/admin/groups/#{group.id}", headers: headers
      }.to change(Group, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(character.reload.group_id).to be_nil
    end
  end
end
