# frozen_string_literal: true

# Vínculo N:N entre sessão e mapa (biblioteca de mapas reutilizáveis).
#
# `schedules.battle_map_id` CONTINUA existindo e passa a significar o mapa
# ATIVO — o que os jogadores estão vendo agora. Esta tabela guarda os mapas
# VINCULADOS à sessão, que o mestre alterna em tempo real.
#
# Manter o FK antigo é deliberado: a visibilidade do jogador
# (`BattleMap#readable_by?`) e ~110 pontos de código resolvem o mapa por ele.
class CreateScheduleBattleMaps < ActiveRecord::Migration[6.0]
  def up
    create_table :schedule_battle_maps do |t|
      t.references :schedule,   null: false, foreign_key: true
      t.references :battle_map, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :schedule_battle_maps, %i[schedule_id battle_map_id],
              unique: true, name: 'index_schedule_battle_maps_unique'

    # Backfill: o vínculo 1:1 atual vira a primeira linha da junção, para
    # nenhuma sessão existente aparecer "sem mapas vinculados".
    execute <<~SQL.squish
      INSERT INTO schedule_battle_maps (schedule_id, battle_map_id, position, created_at, updated_at)
      SELECT id, battle_map_id, 0, NOW(), NOW()
      FROM schedules
      WHERE battle_map_id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    drop_table :schedule_battle_maps
  end
end
