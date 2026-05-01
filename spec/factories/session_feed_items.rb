# frozen_string_literal: true

FactoryBot.define do
  factory :session_feed_item do
    association :schedule
    kind      { 'chat' }
    sequence(:client_id) { |n| "msg-#{n}" }
    posted_at { Time.current }
    payload do
      {
        'kind' => 'chat',
        'id' => client_id,
        'timestamp' => (posted_at || Time.current).to_f * 1000,
        'sessionId' => schedule&.id&.to_s,
        'senderName' => 'Alice',
        'senderRole' => 'player',
        'text' => 'mensagem de teste',
      }
    end

    trait :roll do
      kind { 'roll' }
      sequence(:client_id) { |n| "roll-#{n}" }
      payload do
        {
          'kind' => 'roll',
          'id' => client_id,
          'timestamp' => (posted_at || Time.current).to_f * 1000,
          'sessionId' => schedule&.id&.to_s,
          'playerName' => 'Alice',
          'characterName' => 'PC',
          'type' => 'attack',
          'label' => 'Espada',
          'total' => 18,
          'breakdown' => '1d20+4',
        }
      end
    end

    trait :roll_pending do
      kind { 'roll_pending' }
      sequence(:client_id) { |n| "roll-pending-#{n}" }
      sequence(:roll_group_id) { |n| "rg-#{n}" }
      payload do
        {
          'kind' => 'roll_pending',
          'id' => client_id,
          'rollGroupId' => roll_group_id,
          'timestamp' => (posted_at || Time.current).to_f * 1000,
          'sessionId' => schedule&.id&.to_s,
          'playerName' => 'Alice',
          'characterName' => 'PC',
          'type' => 'attack',
          'label' => 'Espada',
        }
      end
    end
  end
end
