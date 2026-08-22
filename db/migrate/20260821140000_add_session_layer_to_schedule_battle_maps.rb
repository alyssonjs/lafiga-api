# frozen_string_literal: true

# Camada de MESA por sessão (Fase 0).
#
# O mapa guardava tokens, névoa, medidas, desenhos, AoE e projéteis. Como o
# mesmo mapa é usado por várias sessões, esse estado vazava entre mesas — a pior
# parte é a névoa: uma mesa revela salas e a outra abre o mapa já revelado.
#
# Esta migration é ADITIVA: cria as colunas e copia o estado atual para cada
# vínculo. Nada muda de comportamento ainda (o caminho de leitura só passa a
# usar a camada na Fase 1), então o deploy é seguro isolado.
class AddSessionLayerToScheduleBattleMaps < ActiveRecord::Migration[6.0]
  def up
    add_column :schedule_battle_maps, :tokens,              :jsonb, null: false, default: []
    add_column :schedule_battle_maps, :fog,                 :jsonb
    add_column :schedule_battle_maps, :measurements,        :jsonb, null: false, default: []
    add_column :schedule_battle_maps, :drawings,            :jsonb, null: false, default: []
    add_column :schedule_battle_maps, :aoe_placements,      :jsonb, null: false, default: []
    add_column :schedule_battle_maps, :dropped_projectiles, :jsonb, null: false, default: []

    # Backfill: cada sessão recebe uma CÓPIA do estado atual do mapa. Hoje elas
    # compartilham; copiando para todas, nenhuma mesa perde o que já via — e a
    # partir daqui elas divergem.
    say_with_time 'backfill da camada de sessão' do
      ScheduleBattleMap.reset_column_information
      copiados = 0
      ScheduleBattleMap.includes(:battle_map).find_each do |link|
        map = link.battle_map
        next unless map

        link.update_columns(
          tokens: map.creature_tokens,
          fog: map.fog,
          measurements: map.measurements,
          drawings: map.drawings,
          aoe_placements: map.aoe_placements,
          dropped_projectiles: map.dropped_projectiles,
        )
        copiados += 1
      end
      copiados
    end
  end

  def down
    remove_column :schedule_battle_maps, :tokens
    remove_column :schedule_battle_maps, :fog
    remove_column :schedule_battle_maps, :measurements
    remove_column :schedule_battle_maps, :drawings
    remove_column :schedule_battle_maps, :aoe_placements
    remove_column :schedule_battle_maps, :dropped_projectiles
  end
end
