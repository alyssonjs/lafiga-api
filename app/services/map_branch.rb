# frozen_string_literal: true

# A "vertente" do mapa: um mapa vinculado a uma sessão é um RAMO do original,
# daquele grupo, que atravessa as sessões da mesa.
#
# Três estados, e a diferença entre eles é o que faltava:
#   - o MAPA original guarda o estado de fábrica — é o que qualquer mesa recebe
#     ao adicioná-lo pela primeira vez;
#   - a camada da sessão (`ScheduleBattleMap`) guarda o que aquela mesa fez;
#   - uma sessão NOVA da mesma mesa herda a camada da sessão ANTERIOR, não o
#     original: o grupo retoma de onde parou.
#
# Antes disto a camada nascia VAZIA (a mesa perdia tudo a cada sessão) e, quando
# o vínculo nem chegava a existir, a leitura caía no mapa original — que é como
# as áreas de magia de uma luta antiga reapareciam semanas depois.
#
# O tabuleiro (fundo, paredes, terreno, cenário) continua compartilhado: editar
# o mapa no Map Builder vale para todas as mesas. Só os campos de MESA ramificam.
class MapBranch
  FIELDS = MapSessionLayer::SESSION_FIELDS

  class << self
    # Garante a camada desta sessão para este mapa, semeada pela herança.
    # Idempotente: se a camada já existe, devolve-a intacta.
    def ensure!(schedule:, map:)
      return nil if schedule.nil? || map.nil?

      link = ScheduleBattleMap.find_by(schedule_id: schedule.id, battle_map_id: map.id)
      return link if link

      anterior = previous_layer(schedule: schedule, map: map)
      seed = anterior ? FIELDS.index_with { |f| anterior.public_send(f) } : from_original(map)
      # Camada semeada DEPOIS que os NPCs já foram copiados (outro mapa aberto no
      # meio da sessão): o token herdado tem de achar a cópia, não o NPC da
      # sessão anterior.
      if anterior
        seed[:tokens] = ScheduleContinuity.remap_npc_tokens(seed[:tokens], ScheduleContinuity.npc_id_map_for(schedule))
      end

      criado = ScheduleBattleMap.create!(
        schedule_id: schedule.id,
        battle_map_id: map.id,
        position: (schedule.schedule_battle_maps.maximum(:position) || -1) + 1,
        **seed,
      )

      # Instrumentar > deduzir: em 24/08 uma camada nasceu VAZIA em prod
      # (sched 71 / mapa 51) num mapa com 5 criaturas, e o post-mortem foi
      # impossivel — o deploy recriou o contentor e levou os logs do pedido
      # que a criou. Esta linha é o que teria respondido em um grep.
      Rails.logger.info({
        kind: 'map_branch',
        event: 'layer_created',
        schedule_id: schedule.id,
        battle_map_id: map.id,
        group_id: schedule.group_id,
        seed_source: anterior ? "schedule_#{anterior.schedule_id}" : 'original',
        seed_tokens: Array(seed[:tokens]).size,
        map_creature_tokens: Array(map.creature_tokens).size,
      }.to_json)

      # A anomalia exata daquela noite, nomeada: herdar/nascer vazio de um mapa
      # que TEM criaturas é legal pelo design (a mesa pode ter limpado o
      # tabuleiro), mas merece um aviso proprio para saltar num grep de log.
      if Array(seed[:tokens]).empty? && Array(map.creature_tokens).any?
        Rails.logger.warn({
          kind: 'map_branch',
          event: 'layer_created_empty_while_map_has_creatures',
          schedule_id: schedule.id,
          battle_map_id: map.id,
          seed_source: anterior ? "schedule_#{anterior.schedule_id}" : 'original',
        }.to_json)
      end

      criado
    rescue ActiveRecord::RecordNotUnique
      # Corrida entre dois pedidos do mestre — a primeira gravação vale.
      ScheduleBattleMap.find_by(schedule_id: schedule.id, battle_map_id: map.id)
    end

    # De onde a camada nova nasce.
    def seed_for(schedule:, map:)
      anterior = previous_layer(schedule: schedule, map: map)
      return FIELDS.index_with { |f| anterior.public_send(f) } if anterior

      from_original(map)
    end

    # A camada da sessão ANTERIOR deste grupo que tem ESTE mapa.
    #
    # Ordena pela sessão (data, hora, id): "a anterior" é a última que a mesa
    # jogou, não a linha que por acaso foi tocada por último. ⚠️ Só as que
    # vieram ANTES e não foram canceladas — a régua é a mesma dos NPCs
    # (`ScheduleContinuity.earlier_sessions`). Antes valia a data mais recente
    # entre TODAS as irmãs: a #104 herdou o mapa vazio de uma sessão futura e
    # cancelada.
    def previous_layer(schedule:, map:)
      anterior = ScheduleContinuity.earlier_sessions(schedule)
                                   .where(id: ScheduleBattleMap.where(battle_map_id: map.id).select(:schedule_id))
                                   .order(Arel.sql(ScheduleContinuity::ORDEM_CRONOLOGICA_DESC))
                                   .first
      anterior && ScheduleBattleMap.find_by(schedule_id: anterior.id, battle_map_id: map.id)
    end

    # Primeira vez desta mesa com este mapa: recebe o estado de fábrica.
    #
    # Só as criaturas entram na camada — o CENÁRIO continua no tabuleiro, e
    # copiá-lo para cá faria cada objeto aparecer duas vezes (`MapSessionLayer`
    # soma cenário do mapa + tokens da camada).
    def from_original(map)
      {
        tokens: map.creature_tokens,
        fog: map.fog,
        measurements: Array(map.measurements),
        drawings: Array(map.drawings),
        aoe_placements: Array(map.aoe_placements),
        dropped_projectiles: Array(map.dropped_projectiles),
      }
    end
  end
end
