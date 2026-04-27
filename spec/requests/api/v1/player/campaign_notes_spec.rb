# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::CampaignNotesController', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let!(:group) { create(:group) }
  let!(:pc_user) do
    create(
      :user,
      role: player_role,
      name: 'PlayerDiary',
      username: "pc_diary_#{SecureRandom.hex(4)}",
      email: "pc_diary_#{SecureRandom.hex(4)}@lafiga.test"
    )
  end
  let!(:dm_only_user) do
    create(
      :user,
      role: dm_role,
      name: 'DMDiary',
      username: "dm_diary_#{SecureRandom.hex(4)}",
      email: "dm_diary_#{SecureRandom.hex(4)}@lafiga.test"
    )
  end
  let!(:character_in_group) { create(:character, user: pc_user, group: group) }

  let(:pc_headers) { bearer_headers_for(pc_user).merge('Content-Type' => 'application/json') }
  let(:dm_only_headers) { bearer_headers_for(dm_only_user).merge('Content-Type' => 'application/json') }

  describe 'POST /api/v1/player/groups/:group_id/campaign_notes' do
    it 'forbidden quando o utilizador nao tem personagem no grupo' do
      post "/api/v1/player/groups/#{group.id}/campaign_notes",
           params: { campaign_note: { body: 'Teste' } }.to_json,
           headers: dm_only_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'cria quando o utilizador tem personagem no grupo' do
      post "/api/v1/player/groups/#{group.id}/campaign_notes",
           params: { campaign_note: { body: 'Nota do PC', kind: 'recap' } }.to_json,
           headers: pc_headers
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('note', 'body')).to eq('Nota do PC')
    end
  end
end
