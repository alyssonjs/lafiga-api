# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PATCH /api/v1/player/password', type: :request do
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let!(:user) do
    create(
      :user,
      role: player_role,
      password: 'OldPass99',
      password_confirmation: 'OldPass99',
      username: "pwd_user_#{SecureRandom.hex(4)}",
      email: "pwd_#{SecureRandom.hex(4)}@lafiga.test"
    )
  end
  let(:headers) { bearer_headers_for(user).merge('Content-Type' => 'application/json') }

  def patch_password(body)
    patch '/api/v1/player/password', params: body.to_json, headers: headers
  end

  it '401 sem token' do
    patch '/api/v1/player/password',
          params: {}.to_json,
          headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  it '422 quando falta campo' do
    patch_password(current_password: 'OldPass99', password: 'NewPass99')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors']).to be_present
  end

  it '422 quando senha actual errada' do
    patch_password(
      current_password: 'wrong',
      password: 'NewPass99',
      password_confirmation: 'NewPass99'
    )
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].join).to include('incorrecta')
    expect(user.reload.authenticate('OldPass99')).to eq(user)
  end

  it '422 quando confirmacao nao bate' do
    patch_password(
      current_password: 'OldPass99',
      password: 'NewPass99',
      password_confirmation: 'NewPass98'
    )
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it '422 quando nova senha curta' do
    patch_password(
      current_password: 'OldPass99',
      password: '12345',
      password_confirmation: '12345'
    )
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it '200 e actualiza senha e password_changed_at' do
    t0 = Time.current
    patch_password(
      current_password: 'OldPass99',
      password: 'NewPass88',
      password_confirmation: 'NewPass88'
    )
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['password_changed_at']).to be_present
    expect(body['message']).to be_present

    user.reload
    expect(user.authenticate('NewPass88')).to eq(user)
    expect(user.password_changed_at).to be >= t0
  end
end
