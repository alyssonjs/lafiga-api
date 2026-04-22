# frozen_string_literal: true

FactoryBot.define do
  factory :date_dimension do
    sequence(:date) { |n| Date.new(2030, 1, 1) + n.days }
    year  { date.year }
    month { date.month }
    day   { date.day }
    day_of_week { date.wday }
    day_name    { date.strftime('%A') }
    is_weekend  { [0, 6].include?(date.wday) }
    available   { true }
  end
end
