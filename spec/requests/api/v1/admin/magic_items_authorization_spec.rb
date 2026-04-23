# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::MagicItemsController authorization', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  it 'permite GET /api/v1/admin/magic_items para mestre site-wide (papel DM)' do
    get '/api/v1/admin/magic_items', headers: bearer_headers_for(dm_user)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key('magic_items')
  end

  it 'responde 403 para jogador comum (nao 401, para nao disparar logout no cliente)' do
    get '/api/v1/admin/magic_items', headers: bearer_headers_for(player)
    expect(response).to have_http_status(:forbidden)
  end
end
