# frozen_string_literal: true

# Tamanho do TOKEN do NPC, em células por lado (1 Médio, 2 Grande, 3 Enorme,
# 4 Colossal) — o mesmo `TokenSize` do mapa, que o combate já lê para ocupação,
# alcance e área.
#
# ⚠️ O NPC de combate é uma CÓPIA do básico, feita ao "puxar do catálogo", sem
# caminho de volta. `basic_npc_id` é essa volta: é por ele que redimensionar o
# token no mapa grava o tamanho no catálogo. Sem chave estrangeira, como as
# demais referências de token: NPC básico apagado não pode derrubar a sessão.
class AddTokenSizeToNpcs < ActiveRecord::Migration[6.0]
  def change
    add_column :basic_npcs, :token_size, :integer, null: false, default: 1
    add_column :combat_npcs, :token_size, :integer
    add_column :combat_npcs, :basic_npc_id, :bigint
    add_index :combat_npcs, :basic_npc_id
  end
end
