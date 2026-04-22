# frozen_string_literal: true

FactoryBot.define do
  factory :alignment do
    sequence(:api_index) { |n| "spec_align_#{SecureRandom.hex(4)}" }
    sequence(:name) { |n| "Alinhamento #{n}" }
  end

  factory :lawful_good_alignment, parent: :alignment do
    api_index { 'lg' }
    name { 'Leal e Bom' }
  end
end
