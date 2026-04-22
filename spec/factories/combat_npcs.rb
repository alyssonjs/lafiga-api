# frozen_string_literal: true

FactoryBot.define do
  factory :combat_npc do
    association :schedule
    sequence(:name) { |n| "Goblin #{n}" }
    hp_current { 7 }
    hp_max     { 7 }
    ac         { 15 }
    stats      { { 'str' => 8, 'dex' => 14, 'con' => 10, 'int' => 10, 'wis' => 8, 'cha' => 8 } }
  end
end
