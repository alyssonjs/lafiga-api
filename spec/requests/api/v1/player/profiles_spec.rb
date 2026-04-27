# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PATCH /api/v1/player/profile', type: :request do
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let!(:user) do
    create(
      :user,
      role: player_role,
      name: 'Antes Nome',
      username: "prof_#{SecureRandom.hex(4)}",
      email: "antes_#{SecureRandom.hex(4)}@lafiga.test"
    )
  end
  let(:headers) { bearer_headers_for(user).merge('Content-Type' => 'application/json') }

  it '401 sem token' do
    patch '/api/v1/player/profile', params: {}.to_json, headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  it '200 e actualiza nome e email' do
    new_email = "depois_#{SecureRandom.hex(4)}@lafiga.test"
    patch '/api/v1/player/profile',
          params: { name: 'Depois Nome', email: new_email }.to_json,
          headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['name']).to eq('Depois Nome')
    expect(body['email']).to eq(new_email)
    expect(body['username']).to eq(user.username)
    user.reload
    expect(user.name).to eq('Depois Nome')
    expect(user.email).to eq(new_email)
  end

  it '422 quando email duplicado' do
    other = create(
      :user,
      role: player_role,
      email: "ocupado_#{SecureRandom.hex(4)}@lafiga.test",
      username: "other_#{SecureRandom.hex(4)}"
    )
    patch '/api/v1/player/profile',
          params: { name: user.name, email: other.email }.to_json,
          headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
