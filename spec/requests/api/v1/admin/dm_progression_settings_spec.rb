# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::DmProgressionSettingsController', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player_user) { create(:user, role: player_role) }
  let(:dm_headers) { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player_user) }

  describe 'GET /api/v1/admin/dm_progression_settings' do
    it 'returns merged xp_thresholds for DM' do
      get '/api/v1/admin/dm_progression_settings', headers: dm_headers
      expect(response).to have_http_status(:ok)
      xp = response.parsed_body.dig('progression_settings', 'xp_thresholds')
      expect(xp['2']).to eq(300)
    end

    it 'returns 403 for player' do
      get '/api/v1/admin/dm_progression_settings', headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/dm_progression_settings' do
    it 'persists custom thresholds' do
      patch '/api/v1/admin/dm_progression_settings',
            params: { progression_settings: { xp_thresholds: { '5' => 9999 } } },
            headers: dm_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      xp = response.parsed_body.dig('progression_settings', 'xp_thresholds')
      expect(xp['5']).to eq(9999)
      dm_user.reload
      v = dm_user.progression_settings.deep_stringify_keys.dig('xp_thresholds', '5')
      expect(v.to_i).to eq(9999)
    end

    it 'merge: segundo PATCH nao apaga chaves anteriores' do
      u = create(:user, role: dm_role)
      h = bearer_headers_for(u)
      patch '/api/v1/admin/dm_progression_settings',
            params: { progression_settings: { xp_thresholds: { '5' => 1111 } } },
            headers: h,
            as: :json
      expect(response).to have_http_status(:ok)
      patch '/api/v1/admin/dm_progression_settings',
            params: { progression_settings: { xp_thresholds: { '6' => 2222 } } },
            headers: h,
            as: :json
      xp = response.parsed_body.dig('progression_settings', 'xp_thresholds')
      expect(xp['5']).to eq(1111)
      expect(xp['6']).to eq(2222)
    end
  end
end
