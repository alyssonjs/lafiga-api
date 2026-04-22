# frozen_string_literal: true

FactoryBot.define do
  factory :sheet_runtime_state do
    association :sheet
    death_saves          { { 'successes' => 0, 'failures' => 0, 'stable' => false } }
    hit_dice_used        { {} }
    exhaustion           { 0 }
    conditions           { [] }
    concentration        { nil }
    spell_slots_used     { {} }
    class_resources_used { {} }
  end
end
