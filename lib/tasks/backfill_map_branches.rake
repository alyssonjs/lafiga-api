# frozen_string_literal: true

namespace :dnd do
  desc 'Cria a camada de mesa faltante para sessoes que ja tem mapa ativo (idempotente)'
  # Sessao com `battle_map_id` mas SEM `ScheduleBattleMap` lia o mapa ORIGINAL —
  # foi assim que areas de magia de uma luta antiga reapareciam numa sessao nova.
  #
  # Percorre em ordem CRONOLOGICA por (grupo, mapa) para que cada sessao herde a
  # anterior, exatamente como `MapBranch` fara dai em diante. A primeira de cada
  # mesa recebe o estado do original.
  task backfill_map_branches: :environment do
    faltantes = Schedule
      .where.not(battle_map_id: nil)
      .joins(:date_dimension)
      .order('date_dimensions.date ASC NULLS FIRST, schedules.id ASC')

    criados = 0
    ja_ok = 0
    sem_mapa = 0

    faltantes.find_each do |schedule|
      map = schedule.battle_map
      if map.nil?
        sem_mapa += 1
        next
      end
      if ScheduleBattleMap.exists?(schedule_id: schedule.id, battle_map_id: map.id)
        ja_ok += 1
        next
      end

      link = MapBranch.ensure!(schedule: schedule, map: map)
      next unless link

      criados += 1
      origem = MapBranch.previous_layer(schedule: schedule, map: map) ? 'sessao anterior' : 'mapa original'
      puts "  sched #{schedule.id} (#{schedule.title}) mapa #{map.id} <- #{origem}"
    end

    puts "[dnd:backfill_map_branches] criados=#{criados} ja_ok=#{ja_ok} sem_mapa=#{sem_mapa}"
  end
end
