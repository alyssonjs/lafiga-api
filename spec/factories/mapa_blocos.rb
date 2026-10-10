# frozen_string_literal: true

FactoryBot.define do
  factory :mapa_bloco do
    association :battle_map, :vila
    bc { 0 }
    bl { 0 }
    terreno { { 'camadas' => {} } }
    objetos { [] }
  end
end
