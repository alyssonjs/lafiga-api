# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::CharacterDmLevelUnlocksController', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player_user) { create(:user, role: player_role) }
  let(:dm_headers) { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player_user) }

  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let!(:pc) do
    create(:character, user: player_user, name: 'PC', background: 'Teste').tap do |c|
      create(:sheet, character: c, race: race, sub_race: sub_race, current_level: 2)
    end
  end

  describe 'POST /api/v1/admin/characters/:character_id/dm_level_unlock' do
    it 'creates unlock for DM' do
      expect do
        post "/api/v1/admin/characters/#{pc.id}/dm_level_unlock", headers: dm_headers
      end.to change(CharacterDmLevelUnlock, :count).by(1)
      expect(response).to have_http_status(:no_content)
    end

    it 'returns 403 for player' do
      post "/api/v1/admin/characters/#{pc.id}/dm_level_unlock", headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v1/admin/characters/:character_id/dm_level_unlock' do
    before { CharacterDmLevelUnlock.create!(character: pc, unlocked_by_user: dm_user) }

    it 'removes unlock for DM' do
      expect do
        delete "/api/v1/admin/characters/#{pc.id}/dm_level_unlock", headers: dm_headers
      end.to change(CharacterDmLevelUnlock, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
