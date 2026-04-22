# frozen_string_literal: true

FactoryBot.define do
  factory :background do
    sequence(:api_index) { |n| "spec_bg_#{SecureRandom.hex(4)}" }
    sequence(:name) { |n| "Antecedente #{n}" }
    feature_name { 'Traço' }
    feature_desc { 'Descrição' }
  end

  factory :acolyte_background, parent: :background do
    api_index { 'acolyte' }
    name { 'Acólito' }
  end
end
