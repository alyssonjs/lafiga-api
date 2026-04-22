# frozen_string_literal: true

FactoryBot.define do
  factory :sheet_klass do
    association :sheet
    klass do
      Klass.find_or_create_by!(api_index: 'barbarian') do |k|
        k.name = 'Bárbaro'
        k.hit_die = 12
        k.subclass_level = 3
      end
    end
    level { 1 }
    sub_klass { nil }
  end
end
