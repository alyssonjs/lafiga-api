# frozen_string_literal: true

FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Grupo Teste #{n}" }
    day { 1 }
    season { :verao }
  end
end
