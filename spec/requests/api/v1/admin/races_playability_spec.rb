# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Races playability', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  it 'allows a site-wide DM to toggle a race and sub-race playability' do
    race = create(:race, playable: true)
    sub_race = create(:sub_race, race: race, playable: true)

    patch "/api/v1/admin/races/#{race.id}",
          params: { race: { playable: false } },
          headers: bearer_headers_for(dm_user),
          as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(race.reload.playable).to eq(false)
    expect(response.parsed_body.dig('race', 'playable')).to eq(false)

    patch "/api/v1/admin/sub_races/#{sub_race.id}",
          params: { sub_race: { playable: false } },
          headers: bearer_headers_for(dm_user),
          as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(sub_race.reload.playable).to eq(false)
    expect(response.parsed_body.dig('sub_race', 'playable')).to eq(false)
  end

  it 'rejects plain players' do
    race = create(:race)

    patch "/api/v1/admin/races/#{race.id}",
          params: { race: { playable: false } },
          headers: bearer_headers_for(player),
          as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
