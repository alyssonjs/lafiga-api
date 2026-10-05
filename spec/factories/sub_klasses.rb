# frozen_string_literal: true

FactoryBot.define do
  factory :sub_klass do
    association :klass
    sequence(:name) { |n| "Subklass #{n}" }
    sequence(:api_index) { |n| "spec_subklass_#{SecureRandom.hex(4)}" }
    # ⚠️ Lista de níveis, não objeto: o `'{}'` histórico era um shape que nenhum
    # leitor produz (todos fazem `Array(parsed).select { |r| r.is_a?(Hash) }`) e
    # escondia a forma real nas fixtures.
    levels_json { [] }
  end
end
