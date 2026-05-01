# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionFeed::Persist do
  let(:schedule) { create(:schedule) }

  def chat_payload(id: 'msg-1', text: 'oi', timestamp: 1_700_000_000_000)
    {
      'kind' => 'chat',
      'id' => id,
      'timestamp' => timestamp,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => text,
    }
  end

  def roll_pending_payload(rg: 'rg-1', id: 'roll-pending-rg-1', timestamp: 1_700_000_000_000)
    {
      'kind' => 'roll_pending',
      'id' => id,
      'rollGroupId' => rg,
      'timestamp' => timestamp,
      'sessionId' => schedule.id.to_s,
      'playerName' => 'Alice',
      'characterName' => 'PC',
      'type' => 'attack',
      'label' => 'Espada',
    }
  end

  def roll_payload(rg: 'rg-1', id: 'roll-1', timestamp: 1_700_000_001_000, outcome: 'pending')
    {
      'kind' => 'roll',
      'id' => id,
      'rollGroupId' => rg,
      'timestamp' => timestamp,
      'sessionId' => schedule.id.to_s,
      'playerName' => 'Alice',
      'characterName' => 'PC',
      'type' => 'attack',
      'label' => 'Espada',
      'total' => 18,
      'breakdown' => '1d20+4',
      'attackHitOutcome' => outcome,
    }
  end

  describe 'create simple' do
    it 'persists a chat item with timestamp ms convertido' do
      item = described_class.call(schedule_id: schedule.id, normalized: chat_payload)
      expect(item).to be_persisted
      expect(item.kind).to eq('chat')
      expect(item.payload['text']).to eq('oi')
      expect(item.posted_at.to_i).to eq(1_700_000_000)
    end

    it 'é idempotente: dois calls com mesmo client_id geram um único registro' do
      described_class.call(schedule_id: schedule.id, normalized: chat_payload)
      described_class.call(schedule_id: schedule.id, normalized: chat_payload)
      expect(SessionFeedItem.where(schedule_id: schedule.id, client_id: 'msg-1').count).to eq(1)
    end

    it 'recusa kind desconhecido' do
      bad = chat_payload.merge('kind' => 'unknown')
      expect(described_class.call(schedule_id: schedule.id, normalized: bad)).to be_nil
    end
  end

  describe 'roll_pending → roll upsert' do
    it 'substitui o pending pelo roll, preservando posted_at original' do
      pending = described_class.call(schedule_id: schedule.id, normalized: roll_pending_payload)
      original_posted_at = pending.posted_at

      result = described_class.call(schedule_id: schedule.id, normalized: roll_payload)
      expect(result).to be_persisted
      expect(result.id).to eq(pending.id)
      expect(result.kind).to eq('roll')
      expect(result.client_id).to eq('roll-1')
      expect(result.posted_at).to eq(original_posted_at)
      expect(SessionFeedItem.where(schedule_id: schedule.id).count).to eq(1)
    end

    it 'sem pending correspondente, cria roll novo' do
      result = described_class.call(schedule_id: schedule.id, normalized: roll_payload)
      expect(result).to be_persisted
      expect(result.kind).to eq('roll')
    end
  end

  describe 'attack_hit_resolution' do
    it 'atualiza in-place o attackHitOutcome do roll original' do
      described_class.call(schedule_id: schedule.id, normalized: roll_payload)
      resolution = {
        'kind' => 'attack_hit_resolution',
        'id' => 'ahr-1',
        'timestamp' => 1_700_000_002_000,
        'sessionId' => schedule.id.to_s,
        'rollGroupId' => 'rg-1',
        'outcome' => 'hit',
      }
      result = described_class.call(schedule_id: schedule.id, normalized: resolution)
      expect(result.payload['attackHitOutcome']).to eq('hit')
      expect(SessionFeedItem.where(schedule_id: schedule.id, kind: 'attack_hit_resolution').count).to eq(0)
    end

    it 'no-op quando o roll referenciado não existe' do
      resolution = {
        'kind' => 'attack_hit_resolution',
        'id' => 'ahr-orphan',
        'timestamp' => 1_700_000_002_000,
        'sessionId' => schedule.id.to_s,
        'rollGroupId' => 'rg-orphan',
        'outcome' => 'hit',
      }
      expect(described_class.call(schedule_id: schedule.id, normalized: resolution)).to be_nil
    end
  end
end
