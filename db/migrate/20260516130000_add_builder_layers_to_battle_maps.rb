# frozen_string_literal: true

# Fase 2.0 — Map Builder estilo Inkarnate.
#
# Aditivo e seguro: novas colunas JSONB/escalares com default vazio.
# Mapas existentes ficam idênticos (arrays vazios → renderer não desenha
# nada novo; o legado ignora estas colunas). `cells` continua a fonte da
# verdade do JOGO (movimento/paredes/AoE/névoa); estas camadas são apenas
# apresentação aditiva, espelhando o modelo do Inkarnate 2.0:
#   - brush layers  → terrain_layers (textura tile + máscara vetorial)
#   - object layers  → stamps (objetos livres: montanha/floresta/rocha)
#   - paths          → rios/estradas/trilhas
#   - map_effects    → vinheta/grão/papel/iluminação (params, não pixels)
#   - layers         → registro/ordem-z + visível/lock/opacity
#   - map_kind       → 'battle' | 'world' (grid vira camada opcional)
class AddBuilderLayersToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :layers,         :jsonb,  default: [], null: false
    add_column :battle_maps, :terrain_layers, :jsonb,  default: [], null: false
    add_column :battle_maps, :stamps,         :jsonb,  default: [], null: false
    add_column :battle_maps, :paths,          :jsonb,  default: [], null: false
    add_column :battle_maps, :map_effects,    :jsonb,  default: {}, null: false
    add_column :battle_maps, :map_kind,       :string, default: 'battle', null: false
  end
end
