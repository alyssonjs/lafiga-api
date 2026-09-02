# Catálogo de COMPANHEIROS (familiar, montaria, companheiro animal, e os
# vinculados a classe). Até 02/09/2026 os 28 modelos viviam hardcoded no front
# (`companionTemplates.ts`) — o Mestre não criava, não editava e não os via no
# compêndio. Mesma família do `magic_items`: catálogo próprio, CRUD de admin.
#
# Os blocos ricos (stats, ataques, ações) ficam em jsonb porque é o shape que o
# front já consome (`Companion`), e traduzi-los para colunas só criaria uma
# fronteira para manter em dia.
class CreateCompanionTemplates < ActiveRecord::Migration[6.0]
  def change
    create_table :companion_templates do |t|
      t.string  :slug, null: false
      t.string  :name, null: false
      # familiar | beast_companion | mount | greater_mount | homunculus |
      # summon | undead_servant | steel_defender | wildfire_spirit
      t.string  :companion_type, null: false
      # purchased | spell | class_feature
      t.string  :origin, null: false, default: 'purchased'
      t.string  :origin_spell_id
      t.string  :origin_class_feature

      t.string  :creature_type              # Fera, Celestial, Constructo…
      t.string  :size                       # Tiny…Huge
      t.integer :ac
      t.integer :hp_max
      t.string  :speed
      t.integer :prof_bonus, default: 2
      t.integer :carry_capacity             # lb; só faz sentido em montaria

      t.jsonb   :stats, default: {}         # { str, dex, con, int, wis, cha }
      t.jsonb   :attacks, default: []
      t.jsonb   :special_actions, default: []
      # Bandeiras de comportamento (partilha sentidos, entrega toque, temporário,
      # concentração, escala com nível…). jsonb p/ não virar 8 colunas booleanas
      # que só um tipo de companheiro usa.
      t.jsonb   :flags, default: {}

      t.text    :description
      t.string  :source                     # PHB, Homebrew…
      t.text    :tags, array: true, default: []

      t.timestamps
    end

    add_index :companion_templates, :slug, unique: true
    add_index :companion_templates, :companion_type
  end
end
