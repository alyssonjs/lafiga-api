# Catálogo de NPCs BÁSICOS do Mestre — o anão de taverna, o guarda do portão:
# CA, PV, um ataque e pronto.
#
# ⚠️ Tabela própria e não `monsters` com `source: 'homebrew'`: a rodada anterior
# separou justamente NPC de monstro na sessão (o anão listado entre as bestas).
# Guardá-los na mesma tabela reataria o nó do outro lado — e o bestiário é do
# SRD, reimportado por rake.
#
# Espelha o formulário simples de NPC da sessão (`NPCFormData`), para "puxar do
# catálogo" ser cópia direta, sem tradutor.
class CreateBasicNpcs < ActiveRecord::Migration[6.0]
  def change
    create_table :basic_npcs do |t|
      t.string  :slug, null: false
      t.string  :name, null: false
      # "Guarda", "Taverneiro" — o papel que o Mestre procura na lista.
      t.string  :role
      t.text    :notes

      t.integer :hp, null: false, default: 10
      t.integer :ac, null: false, default: 10
      t.integer :initiative_bonus, null: false, default: 0

      # Em PÉS, como `combat_npcs.speed_modes` e o bestiário: uma unidade só.
      t.jsonb   :speed_modes, default: {}
      t.jsonb   :stats, default: {}
      t.jsonb   :attacks, default: []

      # Token pela biblioteca de objetos — referência, como monstro e companheiro.
      t.bigint  :token_map_asset_id

      t.timestamps
    end

    add_index :basic_npcs, :slug, unique: true
    add_index :basic_npcs, :token_map_asset_id
  end
end
