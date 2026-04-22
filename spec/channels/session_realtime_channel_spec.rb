# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionRealtimeChannel, type: :channel do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:player)    { create(:user, role: player_role) }
  let(:outsider)  { create(:user, role: player_role) }

  let(:schedule)  { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group) }

  def token_for(user) = JsonWebToken.encode(user_id: user.id)

  it 'subscribes a member of the group to the schedule stream' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_#{schedule.id}")
  end

  it 'subscribes the DM (site-wide) even without a character in the group' do
    subscribe(token: token_for(dm), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_#{schedule.id}")
  end

  it 'subscribes an outsider (hub read — no character + not DM)' do
    subscribe(token: token_for(outsider), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_#{schedule.id}")
  end

  it 'rejects when the schedule does not exist' do
    subscribe(token: token_for(player), schedule_id: 999_999)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is missing' do
    subscribe(token: '', schedule_id: schedule.id)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is in the blacklist (revoked on logout)' do
    token = token_for(player)
    ValidateJwtToken.create!(token: token)
    subscribe(token: token, schedule_id: schedule.id)
    expect(subscription).to be_rejected
  end
end
