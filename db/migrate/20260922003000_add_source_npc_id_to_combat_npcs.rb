# frozen_string_literal: true

# De qual NPC da sessão ANTERIOR esta cópia saiu.
#
# O NPC de combate é da sessão; a mesa seguinte recebe CÓPIAS, com ids novos.
# Os tokens do mapa guardam `npcId: "npc-<id>"` — e a camada do mapa é herdada
# com os ids da sessão anterior. Sem saber a origem de cada cópia, o token
# herdado apontava para um NPC de outra sessão: aparecia no mapa, mas sem PV,
# sem ficha, fora do combate. Sem chave estrangeira: a sessão anterior pode
# perder o NPC sem derrubar esta.
class AddSourceNpcIdToCombatNpcs < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_npcs, :source_npc_id, :bigint
    add_index :combat_npcs, :source_npc_id
  end
end
