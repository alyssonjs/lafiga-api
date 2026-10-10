# frozen_string_literal: true

FactoryBot.define do
  factory :mundo do
    group
    epoca_em { Time.utc(2026, 10, 9) }
    minuto_na_epoca { 0 }
    fator { 40 }
  end
end
