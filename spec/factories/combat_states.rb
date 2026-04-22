# frozen_string_literal: true

FactoryBot.define do
  factory :combat_state do
    association :schedule
    active { false }
    round  { 0 }
    current_turn_index { 0 }
  end
end
