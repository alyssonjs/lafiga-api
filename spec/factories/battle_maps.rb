# frozen_string_literal: true

FactoryBot.define do
  factory :battle_map do
    association :user
    sequence(:name) { |n| "Mapa Teste #{n}" }
    width { 5 }
    height { 5 }
    cell_size_px { 32 }
    cells { Array.new(5) { Array.new(5, 'empty') } }
    tokens { [] }
    schema_version { 1 }

    trait :with_group do
      association :group
    end

    trait :with_tokens do
      tokens do
        [{ 'id' => 't1', 'name' => 'Goblin', 'color' => '#fff', 'x' => 0, 'y' => 0, 'size' => 1 }]
      end
    end
  end
end
