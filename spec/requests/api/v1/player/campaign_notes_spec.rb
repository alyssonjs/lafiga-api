# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::CampaignNotesController', type: :request do
  let(:player_role) { Role.find_or_create_by!(name: 'LafigaRSpecPlayerOnly') { |r| r.permissions = [] } }
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player) { create(:user, role: player_role) }
  let(:dm) { create(:user, role: dm_role) }
  let(:group) { create(:group) }
  let(:player_headers) { bearer_headers_for(player) }
  let(:dm_headers) { bearer_headers_for(dm) }

  before do
    create(:character, user: player, group: group)
    create(:character, user: dm, group: group)
  end

  describe 'POST /api/v1/player/groups/:group_id/campaign_notes' do
    it 'jogador nao pode fixar nem marcar dm_only — servidor normaliza' do
      payload = {
        campaign_note: {
          body: 'Segredo do jogador',
          pinned: true,
          visibility: 'dm_only',
        },
      }

      post "/api/v1/player/groups/#{group.id}/campaign_notes",
           params: payload,
           headers: player_headers,
           as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body['note']
      expect(json['pinned']).to eq(false)
      expect(json['visibility']).to eq('group')
    end

    it 'mestre pode criar nota fixa e so para o mestre' do
      payload = {
        campaign_note: {
          body: 'Nota do mestre',
          pinned: true,
          visibility: 'dm_only',
        },
      }

      post "/api/v1/player/groups/#{group.id}/campaign_notes",
           params: payload,
           headers: dm_headers,
           as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body['note']
      expect(json['pinned']).to eq(true)
      expect(json['visibility']).to eq('dm_only')
    end
  end

  describe 'GET /api/v1/player/groups/:group_id/campaign_notes' do
    it 'mestre ve nota dm_only de outro usuario' do
      note = CampaignNote.create!(
        group: group,
        user: player,
        body: 'Privado',
        kind: :note,
        visibility: :dm_only,
        pinned: false,
      )

      get "/api/v1/player/groups/#{group.id}/campaign_notes", headers: dm_headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['notes'].map { |n| n['id'] }
      expect(ids).to include(note.id)
    end

    it 'outro jogador nao ve nota dm_only alheia' do
      other = create(:user, role: player_role)
      create(:character, user: other, group: group)

      note = CampaignNote.create!(
        group: group,
        user: player,
        body: 'Só DM',
        kind: :note,
        visibility: :dm_only,
        pinned: false,
      )

      get "/api/v1/player/groups/#{group.id}/campaign_notes", headers: bearer_headers_for(other)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['notes'].map { |n| n['id'] }
      expect(ids).not_to include(note.id)
    end
  end

  describe 'PUT /api/v1/player/campaign_notes/:id' do
    it 'mestre pode fixar nota de outro autor' do
      note = CampaignNote.create!(
        group: group,
        user: player,
        body: 'Do jogador',
        kind: :note,
        visibility: :group,
        pinned: false,
      )

      put "/api/v1/player/campaign_notes/#{note.id}",
          params: { campaign_note: { pinned: true } },
          headers: dm_headers,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['note']['pinned']).to eq(true)
      expect(note.reload.pinned).to eq(true)
    end
  end
end
