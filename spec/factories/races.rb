# frozen_string_literal: true

FactoryBot.define do
  factory :race do
    sequence(:name) { |n| "Spec Race #{n}" }
    sequence(:api_index) { |n| "spec_race_#{n}_#{SecureRandom.hex(4)}" }
  end
end
