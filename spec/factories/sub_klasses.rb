# frozen_string_literal: true

FactoryBot.define do
  factory :sub_klass do
    association :klass
    sequence(:name) { |n| "Subklass #{n}" }
    sequence(:api_index) { |n| "spec_subklass_#{SecureRandom.hex(4)}" }
    levels_json { '{}' }
  end
end
