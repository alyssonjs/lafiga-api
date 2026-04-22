# frozen_string_literal: true

FactoryBot.define do
  factory :character do
    association :user
    sequence(:name) { |n| "Personagem #{n}" }
    background { 'Antecedente de teste' }
    status { :active }
  end
end
