# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Backgrounds', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }

  describe 'GET /api/v1/admin/backgrounds' do
    it 'returns 401 without auth' do
      get '/api/v1/admin/backgrounds'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for plain player (DM/Admin only)' do
      get '/api/v1/admin/backgrounds', headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end

    it 'lists backgrounds' do
      Background.create!(
        api_index: 'z_spec_test_bg',
        name: 'Z Spec BG',
        rules: {
          'id' => 'z_spec_test_bg',
          'name' => 'Z Spec BG',
          'skills' => [],
          'tools' => [],
          'languages' => { 'choose' => 0 },
          'equipment' => [],
          'feature' => { 'name' => 'A', 'desc' => 'B' }
        }
      )
      get '/api/v1/admin/backgrounds', headers: headers
      expect(response).to have_http_status(:ok)
      idx = response.parsed_body['backgrounds'].map { |b| b['api_index'] }
      expect(idx).to include('z_spec_test_bg')
    end
  end

  describe 'PATCH /api/v1/admin/backgrounds/:api_index' do
    let!(:bg) do
      Background.create!(
        api_index: 'admin_patch_bg_spec',
        name: 'Patch Me',
        rules: {
          'id' => 'admin_patch_bg_spec',
          'skills' => ['Atletismo'],
          'tools' => [],
          'languages' => { 'choose' => 0 },
          'equipment' => [],
          'feature' => { 'name' => 'OLD', 'desc' => 'old' }
        }
      )
    end

    it 'deep-merges rules' do
      BackgroundRules.clear_cache!
      patch "/api/v1/admin/backgrounds/#{bg.api_index}",
            params: { background: { rules: { 'skills' => ['Intuição'] } } }.to_json,
            headers: headers
      expect(response).to have_http_status(:ok)
      bg.reload
      expect(bg.rules['skills']).to eq(['Intuição'])
      expect(bg.rules.dig('feature', 'name')).to eq('OLD')
    end
  end
end
