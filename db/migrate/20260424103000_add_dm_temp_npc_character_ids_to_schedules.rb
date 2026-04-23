# frozen_string_literal: true

# PJ de jogador tratado como NPC pelo mestre durante a sessão (ex.: dominação).
# Não altera a ficha; só o estado da sessão. Não copiado para a sessão seguinte.
class AddDmTempNpcCharacterIdsToSchedules < ActiveRecord::Migration[6.0]
  def change
    add_column :schedules, :dm_temp_npc_character_ids, :jsonb, null: false, default: []
  end
end
