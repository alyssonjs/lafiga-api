# frozen_string_literal: true

# Override editável (DM) das "Magias do Círculo por Terreno" do Druida
# Círculo da Terra. `null` = usa o catálogo canônico estático
# (`LAND_TERRAIN_SPELLS` no front). Estrutura espelhada de `LandTerrainSpells[]`:
#   [{ "terrain": "Ártico",
#      "spells": [{ "level": 3, "spellLevel": 2, "spells": ["...", "..."] }, ...] },
#    ...]
class AddTerrainSpellsToSubKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :sub_klasses, :terrain_spells, :jsonb, null: true, default: nil
  end
end
