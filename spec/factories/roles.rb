# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    sequence(:name) { |n| "Player #{n}" }
    permissions { [] }
  end
end
