# frozen_string_literal: true

FactoryBot.define do
  factory :sheet do
    association :character
    association :race
    # sub_race precisa pertencer a MESMA race do sheet (validacao
    # `Sub race deve pertencer à raça selecionada`). Antes a factory
    # criava :sub_race independente, vinculado a uma race recem-criada
    # pela sua propria factory — quebrava o save em qualquer spec que
    # usasse `create(:sheet)` sem override explicito.
    sub_race { association(:sub_race, race: race) }
    current_level { 1 }
    str { 16 }
    dex { 14 }
    con { 14 }
    int { 8 }
    wis { 10 }
    cha { 10 }
    hp_max { 14 }
    hp_current { 14 }
    temp_hp { 0 }
    metadata { {} }
    race_summary { {} }
    class_summary { {} }
    background_summary { {} }
  end
end
