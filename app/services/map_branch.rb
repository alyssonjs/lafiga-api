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

      ScheduleBattleMap.create!(
        schedule_id: schedule.id,
        battle_map_id: map.id,
        position: (schedule.schedule_battle_maps.maximum(:position) || -1) + 1,
        **seed_for(schedule: schedule, map: map),
      )
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

    # A camada mais recente DESTE grupo para ESTE mapa, fora desta sessão.
    #
    # Ordena pela sessão (data, depois id): "a anterior" é a última que a mesa
    # jogou, não a linha que por acaso foi tocada por último.
    def previous_layer(schedule:, map:)
      return nil if schedule.group_id.blank?

      irmas = Schedule.where(group_id: schedule.group_id).where.not(id: schedule.id)
      ScheduleBattleMap
        .where(battle_map_id: map.id, schedule_id: irmas.select(:id))
        .joins(schedule: :date_dimension)
        .order('date_dimensions.date DESC NULLS LAST, schedules.id DESC')
        .first
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
