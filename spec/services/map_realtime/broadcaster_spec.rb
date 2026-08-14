# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapRealtime::Broadcaster, type: :service do
  let(:user) { create(:user) }
  let(:map)  { create(:battle_map, user: user) }

  def stream
    MapChannel.stream_name(map)
  end

  describe '.token_moved' do
    it 'broadcasts envelope with event token_moved + tokenId/x/y/version/actor_id' do
      expect {
        described_class.token_moved(map, 'tok-1', 3, 4, actor: user)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('token_moved')
        expect(data['payload']).to include('tokenId' => 'tok-1', 'x' => 3, 'y' => 4)
        expect(data.dig('payload', 'version')).to be_a(Integer)
        expect(data['actor_id']).to eq(user.id)
      }
    end

    it 'propagates correlation metadata without changing the payload' do
      expect {
        described_class.token_moved(
          map, 'tok-1', 3, 4, actor: user,
          command_id: 'cmd-map-123', client_id: 'cli-tab-123'
        )
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event_id']).to be_present
        expect(data['command_id']).to eq('cmd-map-123')
        expect(data['client_id']).to eq('cli-tab-123')
        expect(data['payload']).to include('tokenId' => 'tok-1', 'x' => 3, 'y' => 4)
        expect(data.dig('payload', 'version')).to be_a(Integer)
      }
    end
  end

  describe '.tokens_changed' do
    it 'broadcasts the new tokens array' do
      tokens = [{ 'id' => 't1', 'x' => 0, 'y' => 0, 'name' => 'goblin' }]
      expect {
        described_class.tokens_changed(map, tokens, actor: user)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('tokens_changed')
        expect(data['payload']['tokens']).to eq(tokens)
        expect(data.dig('payload', 'version')).to be_a(Integer)
      }
    end
  end

  describe '.tokens_patched' do
    it 'broadcasts granular fields and persistence version' do
      mutation = {
        additions: [],
        patches: [{ token_id: 't1', changes: { 'x' => 3 }, unset: [] }],
        delete_ids: [],
      }
      expect {
        described_class.tokens_patched(map, mutation, version: 123, actor: user)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('tokens_patched')
        expect(data.dig('payload', 'patches', 0)).to include(
          'tokenId' => 't1', 'changes' => { 'x' => 3 }, 'unset' => [],
        )
        expect(data.dig('payload', 'version')).to eq(123)
      }
    end
  end

  describe '.cells_changed' do
    it 'broadcasts the new cells matrix' do
      cells = [%w[empty stone], %w[stone empty]]
      expect {
        described_class.cells_changed(map, cells)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('cells_changed')
        expect(data['payload']['cells']).to eq(cells)
      }
    end
  end

  describe '.fog_changed' do
    it 'broadcasts the new fog matrix' do
      fog = [[true, false], [false, true]]
      expect {
        described_class.fog_changed(map, fog)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('fog_changed')
        expect(data['payload']['fog']).to eq(fog)
      }
    end
  end

  describe '.map_updated' do
    it 'broadcasts the full payload' do
      payload = { 'id' => map.id, 'name' => 'X' }
      expect {
        described_class.map_updated(map, payload)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('map_updated')
        expect(data['payload']['battle_map']).to eq(payload)
      }
    end
  end

  describe '.map_deleted' do
    it 'broadcasts only the id' do
      expect {
        described_class.map_deleted(map.id)
      }.to have_broadcasted_to("map_#{map.id}").with { |data|
        expect(data['event']).to eq('map_deleted')
        expect(data['payload']).to eq('id' => map.id)
      }
    end
  end

  describe '.broadcast' do
    it 'raises on unknown event' do
      expect { described_class.broadcast(map, :unknown_event, {}) }.to raise_error(ArgumentError)
    end
  end
end
