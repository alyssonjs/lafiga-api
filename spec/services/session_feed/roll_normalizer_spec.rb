# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionFeed::RollNormalizer, type: :service do
  let(:base) do
    {
      'kind' => 'roll', 'id' => 'roll-1', 'rollGroupId' => 'rg-1',
      'timestamp' => 1_700_000_000_000, 'revealAt' => 1_700_000_001_650,
      'playerName' => 'Player', 'characterName' => 'Lira',
      'senderRole' => 'player', 'type' => 'attack', 'label' => 'Arco',
      'total' => 18, 'breakdown' => '14 + 4', 'attackHitOutcome' => 'pending',
      'targetAC' => 15, 'targetTokenId' => 'target', 'attackerTokenId' => 'lira',
    }
  end

  it 'normaliza o contrato compartilhado de uma rolagem de ataque' do
    result = described_class.call(schedule_id: 69, item: base)

    expect(result).to include(
      'kind' => 'roll', 'sessionId' => '69', 'id' => 'roll-1',
      'rollGroupId' => 'rg-1', 'total' => 18, 'targetAC' => 15,
      'revealAt' => 1_700_000_001_650,
    )
  end

  it 'limita revealAt e rejeita payload não-roll' do
    result = described_class.call(
      schedule_id: 69,
      item: base.merge('revealAt' => base['timestamp'] + 60_000),
    )

    expect(result['revealAt']).to eq(base['timestamp'] + 5_000)
    expect(described_class.call(schedule_id: 69, item: base.merge('kind' => 'chat'))).to be_nil
  end
end
