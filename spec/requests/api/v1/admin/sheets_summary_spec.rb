# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::SheetsController summary', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player_user) { create(:user, role: player_role) }
  let(:dm_headers) { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player_user) }

  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: player_user, name: 'PC do jogador', background: 'Teste') }
  let(:ranger_klass) do
    Klass.find_or_create_by!(api_index: 'ranger') do |k|
      k.name = 'Patrulheiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end
  let!(:sheet) do
    create(
      :sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      current_level: 3,
      str: 10, dex: 16, con: 13, int: 8, wis: 12, cha: 10,
      hp_max: 25,
      hp_current: 25,
      metadata: {'current_level' => 3},
      race_summary: {'name' => 'Humano', 'speed_ft' => 30},
      class_summary: {'name' => 'Patrulheiro'}
    )
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: ranger_klass, level: 3) }

  describe 'GET /api/v1/admin/sheets/:id/summary' do
    it 'allows a site-wide DM to read summary for another user sheet' do
      get "/api/v1/admin/sheets/#{sheet.id}/summary?sync=true", headers: dm_headers

      expect(response).to have_http_status(:ok), -> { response.body }
      summary = response.parsed_body['summary']
      expect(summary).to be_a(Hash)
      klasses = summary['klasses'] || summary[:klasses]
      expect(klasses).to be_an(Array)
      expect(klasses[0]['name'] || klasses[0][:name]).to eq('Patrulheiro')
    end

    it 'returns 403 for a plain player' do
      get "/api/v1/admin/sheets/#{sheet.id}/summary", headers: player_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
