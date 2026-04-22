# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapChannel, type: :channel do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:owner)     { create(:user, role: player_role) }
  let(:member)    { create(:user, role: player_role) }
  let(:outsider)  { create(:user, role: player_role) }

  let(:group) { create(:group) }
  let!(:member_character) { create(:character, user: member, group: group) }

  let(:private_map) { create(:battle_map, user: owner) }
  let(:shared_map)  { create(:battle_map, user: owner, group: group) }

  def token_for(user) = JsonWebToken.encode(user_id: user.id)

  it 'subscribes the owner to private map stream' do
    subscribe(token: token_for(owner), map_id: private_map.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("map_#{private_map.id}")
  end

  it 'subscribes a group member to a shared map' do
    subscribe(token: token_for(member), map_id: shared_map.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("map_#{shared_map.id}")
  end

  it 'subscribes the DM (site-wide) to any map' do
    subscribe(token: token_for(dm), map_id: private_map.id)
    expect(subscription).to be_confirmed
  end

  it 'rejects an outsider for a shared map not linked to any schedule' do
    subscribe(token: token_for(outsider), map_id: shared_map.id)
    expect(subscription).to be_rejected
  end

  it 'subscribes an outsider when the map is linked to a schedule (hub read)' do
    dm_map = create(:battle_map, user: dm, group: nil)
    create(:schedule, group: group, battle_map: dm_map)
    subscribe(token: token_for(outsider), map_id: dm_map.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("map_#{dm_map.id}")
  end

  it 'rejects an outsider trying to read a private map of another user' do
    subscribe(token: token_for(outsider), map_id: private_map.id)
    expect(subscription).to be_rejected
  end

  it 'rejects when the map does not exist' do
    subscribe(token: token_for(owner), map_id: 999_999)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is missing' do
    subscribe(token: '', map_id: private_map.id)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is in the blacklist (revoked on logout)' do
    token = token_for(owner)
    ValidateJwtToken.create!(token: token)
    subscribe(token: token, map_id: private_map.id)
    expect(subscription).to be_rejected
  end
end
