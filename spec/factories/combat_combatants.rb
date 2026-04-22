# frozen_string_literal: true

FactoryBot.define do
  factory :combat_combatant do
    association :combat_state
    association :combatable, factory: :character

    sequence(:name) { |n| "Combatente #{n}" }
    initiative { 10 }
    initiative_bonus { 2 }
    tie_break_dex { 14 }
    sequence(:position) { |n| n }
    hp_current { 20 }
    hp_max     { 20 }
    ac         { 14 }
    temp_hp    { 0 }

    trait :npc do
      association :combatable, factory: :combat_npc
    end

    trait :pc do
      association :combatable, factory: :character
    end
  end
end
