# frozen_string_literal: true

FactoryBot.define do
  factory :sub_race do
    association :race
    sequence(:name) { |n| "Sub #{n}" }
    sequence(:api_index) { |n| "spec_sub_#{SecureRandom.hex(4)}" }
  end
end
