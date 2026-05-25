# frozen_string_literal: true

# Magias bônus declaradas por subclasse homebrew (Compêndio).
#
# Shape do JSONB (camelCase, espelha `SubclassData.bonusSpells/Mode`):
#   { "mode": "always_known" | "always_prepared" | "expanded_list",
#     "entries": [ { "level": 1, "spellLevel": 0, "spells": ["Chamas Sagradas"] } ] }
#
# Casos de uso:
#  - "always_known" (Bruxo Arcanjo Vingador): magia conhecida automaticamente,
#    NÃO conta contra cantripsKnown nem ocupa slot do Pacto do Tomo.
#  - "always_prepared" (Clérigo Domínio, padrão): preparada sem ocupar limite.
#  - "expanded_list" (Bruxo Patron): expande o pool de seleção.
class AddBonusSpellsToSubKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :sub_klasses, :bonus_spells, :jsonb
  end
end
