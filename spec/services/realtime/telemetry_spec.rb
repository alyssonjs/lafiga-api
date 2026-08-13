# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Realtime::Telemetry, type: :service do
  describe '.emit' do
    it 'logs only the operational allowlist' do
      expect(Rails.logger).to receive(:info) do |line|
        payload = JSON.parse(line)
        expect(payload).to include(
          'kind' => 'realtime_trace',
          'stage' => 'command_received',
          'domain' => 'map',
          'command_id' => 'cmd-map-123',
          'client_id' => 'cli-tab-123',
        )
        expect(payload).not_to have_key('authorization')
        expect(payload).not_to have_key('payload')
      end

      described_class.emit(
        stage: 'command_received',
        domain: 'map',
        command_id: 'cmd-map-123',
        client_id: 'cli-tab-123',
        authorization: 'Bearer secret',
        payload: { private: true },
      )
    end

    it 'drops unsafe identifiers instead of logging them' do
      expect(Rails.logger).to receive(:info) do |line|
        payload = JSON.parse(line)
        expect(payload).not_to have_key('command_id')
        expect(payload).not_to have_key('client_id')
      end

      described_class.emit(
        stage: 'event_received',
        domain: 'feed',
        command_id: 'Bearer abc.def.ghi',
        client_id: '<script>alert(1)</script>',
      )
    end
  end

  describe '.identifier' do
    it 'accepts transport-safe IDs and caps their length' do
      expect(described_class.identifier('cmd-map_1:abc')).to eq('cmd-map_1:abc')
      expect(described_class.identifier('x' * 129)).to be_nil
    end
  end
end
