# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::Broadcaster, type: :service do
  let(:schedule) { create(:schedule) }
  let(:cs)       { create(:combat_state, schedule: schedule, active: true, round: 2) }
  let(:user)     { create(:user) }
  let(:char)     { create(:character, user: user, group: schedule.group) }

  def stream
    SessionRealtimeChannel.stream_name_for(schedule.id)
  end

  describe '.state_changed' do
    it 'broadcasts state with envelope { event, payload, emitted_at }' do
      expect {
        described_class.state_changed(cs)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('state_changed')
        expect(data['payload']).to include('id' => cs.id, 'active' => true, 'round' => 2)
        expect(data['emitted_at']).to be_present
      }
    end

    it 'does nothing when combat_state is nil' do
      expect { described_class.state_changed(nil) }.not_to have_broadcasted_to(stream)
    end
  end

  describe '.combatant_upserted' do
    it 'broadcasts the serialized combatant' do
      combatant = create(:combat_combatant, combat_state: cs, combatable: char, position: 0)
      expect {
        described_class.combatant_upserted(combatant)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('combatant_upserted')
        expect(data['payload']).to include('id' => combatant.id, 'type' => 'pc')
      }
    end
  end

  describe '.combatant_destroyed' do
    it 'broadcasts only the id' do
      expect {
        described_class.combatant_destroyed(schedule_id: schedule.id, combatant_id: 42)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('combatant_destroyed')
        expect(data['payload']).to eq('id' => 42)
      }
    end
  end

  describe '.npc_upserted' do
    it 'broadcasts the serialized npc' do
      npc = create(:combat_npc, schedule: schedule)
      expect {
        described_class.npc_upserted(npc)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('npc_upserted')
        expect(data['payload']['id']).to eq(npc.id)
      }
    end
  end

  describe '.log_appended' do
    it 'broadcasts the serialized log' do
      log = create(:session_log, schedule: schedule, message: 'Algo aconteceu')
      expect {
        described_class.log_appended(log)
      }.to have_broadcasted_to(stream).with { |data|
        expect(data['event']).to eq('log_appended')
        expect(data['payload']).to include('id' => log.id, 'message' => 'Algo aconteceu')
      }
    end
  end

  describe '.silently' do
    it 'suppresses broadcasts inside the block' do
      combatant = create(:combat_combatant, combat_state: cs, combatable: char, position: 0)
      expect {
        described_class.silently do
          described_class.state_changed(cs)
          described_class.combatant_upserted(combatant)
        end
      }.not_to have_broadcasted_to(stream)
    end

    it 'restores normal broadcasting after the block' do
      described_class.silently { } # no-op
      expect {
        described_class.state_changed(cs)
      }.to have_broadcasted_to(stream)
    end

    it 'restores even on exception' do
      expect {
        described_class.silently { raise 'boom' }
      }.to raise_error('boom')

      expect(described_class.suppressed?).to be false
    end
  end
end
