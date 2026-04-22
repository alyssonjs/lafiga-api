# frozen_string_literal: true

FactoryBot.define do
  factory :klass do
    sequence(:name) { |n| "Spec Class #{n}" }
    sequence(:api_index) { |n| "spec_klass_#{SecureRandom.hex(5)}" }
    hit_die { 8 }
    subclass_level { 3 }
  end
end
