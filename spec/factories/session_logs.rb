# frozen_string_literal: true

FactoryBot.define do
  factory :session_log do
    association :schedule
    kind    { :narrative }
    actor   { 'DM' }
    message { 'Log de teste' }
    posted_at { Time.current }
  end
end
