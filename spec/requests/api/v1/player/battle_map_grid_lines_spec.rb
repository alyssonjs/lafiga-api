# frozen_string_literal: true

require 'rails_helper'

# Opacidade das LINHAS da grade — distinta do `grid_opacity`, que (apesar do
# nome) e o veu de terreno sobre a arte. 0 = grade invisivel a pedido do mestre.
RSpec.describe 'Api::V1::Player::BattleMaps linhas da grade', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }
  let(:map)     { create(:battle_map, user: dm) }

  it 'nasce visivel (default 1.0) e sai no payload' do
    get "/api/v1/player/battle_maps/#{map.id}", headers: bearer_headers_for(dm)

    expect(response.parsed_body['battle_map']['gridLinesOpacity']).to eq(1.0)
  end

  it 'o mestre esconde a grade e o valor persiste' do
    patch "/api/v1/player/battle_maps/#{map.id}",
          params: { battle_map: { grid_lines_opacity: 0 } },
          headers: bearer_headers_for(dm), as: :json

    expect(response).to have_http_status(:ok)
    expect(map.reload.grid_lines_opacity).to eq(0.0)

    get "/api/v1/player/battle_maps/#{map.id}", headers: bearer_headers_for(dm)
    expect(response.parsed_body['battle_map']['gridLinesOpacity']).to eq(0.0)
  end

  it 'meio-termo tambem persiste (grade esmaecida sobre a arte)' do
    patch "/api/v1/player/battle_maps/#{map.id}",
          params: { battle_map: { grid_lines_opacity: 0.35 } },
          headers: bearer_headers_for(dm), as: :json

    expect(map.reload.grid_lines_opacity).to eq(0.35)
  end
end
