# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionFeedChannel, type: :channel do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:player)    { create(:user, role: player_role) }
  let(:outsider)  { create(:user, role: player_role) }

  let(:schedule)  { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group) }

  def token_for(user) = JsonWebToken.encode(user_id: user.id)

  let(:valid_chat) do
    {
      'kind' => 'chat',
      'id' => 'msg-1',
      'timestamp' => 1_700_000_000_000,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => 'Olá',
    }
  end

  let(:valid_roll) do
    {
      'kind' => 'roll',
      'id' => 'roll-1',
      'timestamp' => 1_700_000_000_001,
      'sessionId' => schedule.id.to_s,
      'playerName' => 'Alice',
      'characterName' => 'PC',
      'type' => 'attack',
      'label' => 'Espada',
      'total' => 18,
      'breakdown' => '1d20+4',
    }
  end

  it 'subscribes a member of the group to the feed stream' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_feed_#{schedule.id}")
  end

  it 'subscribes when schedule_id uses api-NN UI prefix (same as GameSession URL id)' do
    subscribe(token: token_for(player), schedule_id: "api-#{schedule.id}")
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_feed_#{schedule.id}")
  end

  it 'subscribes the DM (site-wide)' do
    subscribe(token: token_for(dm), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_feed_#{schedule.id}")
  end

  it 'subscribes an outsider (hub read — mirrors SessionRealtimeChannel)' do
    subscribe(token: token_for(outsider), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
  end

  it 'rejects when the schedule does not exist' do
    subscribe(token: token_for(player), schedule_id: 999_999)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is missing' do
    subscribe(token: '', schedule_id: schedule.id)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is blacklisted' do
    token = token_for(player)
    ValidateJwtToken.create!(token: token)
    subscribe(token: token, schedule_id: schedule.id)
    expect(subscription).to be_rejected
  end

  it 'broadcasts a normalized chat item on feed_item' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect do
      perform :feed_item, item: valid_chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'text' => 'Olá', 'sessionId' => schedule.id.to_s),
    )
  end

  it 'broadcasts chat with cardAccentColor when valid hex' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    chat = valid_chat.merge('cardAccentColor' => '#9b59b6')
    expect do
      perform :feed_item, item: chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'cardAccentColor' => '#9b59b6'),
    )
  end

  it 'strips invalid cardAccentColor from chat' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    chat = valid_chat.merge('cardAccentColor' => 'javascript:alert(1)')
    expect do
      perform :feed_item, item: chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      satisfy { |p| p['kind'] == 'chat' && p['text'] == 'Olá' && !p.key?('cardAccentColor') },
    )
  end

  it 'broadcasts a normalized roll item on feed_item' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect do
      perform :feed_item, item: valid_roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'roll', 'total' => 18),
    )
  end

  it 'broadcasts chat with sticker data URL (tiny png)' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    png_b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    data_url = "data:image/png;base64,#{png_b64}"
    sticker_chat = {
      'kind' => 'chat',
      'id' => 'msg-sticker-data',
      'timestamp' => 1_700_000_000_004,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => '',
      'stickerUrl' => data_url,
    }
    expect do
      perform :feed_item, item: sticker_chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'stickerUrl' => data_url, 'text' => ''),
    )
  end

  it 'does not broadcast chat when sticker data URL is not a real image' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    fake_png = Base64.strict_encode64('not-a-real-png-bytes!!')
    sticker_chat = {
      'kind' => 'chat',
      'id' => 'msg-sticker-bad',
      'timestamp' => 1_700_000_000_005,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => '',
      'stickerUrl' => "data:image/png;base64,#{fake_png}",
    }
    expect do
      perform :feed_item, item: sticker_chat
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'broadcasts chat with gif and empty text' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    gif_chat = {
      'kind' => 'chat',
      'id' => 'msg-gif',
      'timestamp' => 1_700_000_000_003,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => '',
      'gifUrl' => 'https://media.tenor.com/abc123/example.gif',
    }
    expect do
      perform :feed_item, item: gif_chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'gifUrl' => 'https://media.tenor.com/abc123/example.gif', 'text' => ''),
    )
  end

  it 'broadcasts roll_pending for suspense phase' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    pending = {
      'kind' => 'roll_pending',
      'id' => 'roll-pending-rg1',
      'rollGroupId' => 'rg-1',
      'timestamp' => 1_700_000_000_002,
      'sessionId' => schedule.id.to_s,
      'playerName' => 'Mestre',
      'characterName' => 'Grog',
      'type' => 'skill',
      'label' => 'Intimidacao',
    }
    expect do
      perform :feed_item, item: pending
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'roll_pending', 'rollGroupId' => 'rg-1', 'label' => 'Intimidacao'),
    )
  end

  it 'does not broadcast junk kind' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect do
      perform :feed_item, item: { 'kind' => 'system', 'text' => 'x' }
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'does not broadcast when rate limited' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    allow(SessionFeed::RateLimit).to receive(:allow?).and_return(false)
    expect do
      perform :feed_item, item: valid_chat
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end
end
