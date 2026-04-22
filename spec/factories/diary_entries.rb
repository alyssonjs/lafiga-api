# frozen_string_literal: true

FactoryBot.define do
  factory :diary_entry do
    association :character
    sequence(:title) { |n| "Entrada ##{n}" }
    content     { 'Conteudo da entrada de diario.' }
    font_family { 'Caveat' }
    font_size   { 16 }
    text_color  { '#3e2723' }
    page_color  { '#f5e6d3' }
  end
end
