# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "rspec_user_#{n}_#{SecureRandom.hex(4)}@lafiga.test" }
    sequence(:username) { |n| "rspec_#{n}_#{SecureRandom.hex(4)}" }
    password { 'password123' }
    password_confirmation { 'password123' }
    association :role
  end
end
