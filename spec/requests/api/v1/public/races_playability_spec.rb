# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::Races playability', type: :request do
  it 'exposes playable flags for races and sub-races' do
    race = create(:race, name: 'Povo Escondido', playable: false)
    sub_race = create(:sub_race, race: race, name: 'Linhagem Secreta', playable: false)

    get '/api/v1/public/races'

    expect(response).to have_http_status(:ok)
    row = response.parsed_body['races'].find { |r| r['id'] == race.id }
    expect(row['playable']).to eq(false)
    expect(row['sub_races'].find { |sr| sr['id'] == sub_race.id }['playable']).to eq(false)
  end
end
