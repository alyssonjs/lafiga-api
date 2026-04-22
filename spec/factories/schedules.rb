# frozen_string_literal: true

FactoryBot.define do
  factory :schedule do
    association :group
    association :date_dimension
    sequence(:title) { |n| "Sessao Teste #{n}" }
    status { :reserved }
  end
end
