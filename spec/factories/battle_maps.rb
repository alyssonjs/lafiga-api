# frozen_string_literal: true

FactoryBot.define do
  factory :battle_map do
    association :user
    sequence(:name) { |n| "Mapa Teste #{n}" }
    width { 5 }
    height { 5 }
    cell_size_px { 32 }
    cells { Array.new(5) { Array.new(5, 'empty') } }
    tokens { [] }
    schema_version { 1 }

    trait :with_group do
      association :group
    end

    # A CASCA do mapa da vila (L1.2): o conteúdo mora em `mapa_blocos`, e `cells` fica vazio. 100×100 = 3×3 blocos de
    # 40, com os da última coluna e da última linha menores (20).
    trait :vila do
      map_kind { 'vila' }
      armazenamento { 'blocos' }
      width { 100 }
      height { 100 }
      cells { [] }
      semente { 11 }
    end

    trait :with_tokens do
      tokens do
        [{ 'id' => 't1', 'name' => 'Goblin', 'color' => '#fff', 'x' => 0, 'y' => 0, 'size' => 1 }]
      end
    end
  end
end
