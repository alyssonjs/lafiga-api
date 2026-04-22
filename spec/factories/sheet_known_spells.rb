# frozen_string_literal: true

FactoryBot.define do
  factory :sheet_known_spell do
    association :sheet_klass
    association :spell
    source { 'class' }
    gained_at_class_level { 1 }
    uses_per_rest { nil }
    uses_remaining { 0 }
  end
end
