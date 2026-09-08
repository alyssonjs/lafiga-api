# frozen_string_literal: true

# Promover / repor VARIANTES de um mapa.
#
# O mapa da lista é o ORIGINAL (o estado de fábrica); cada mesa que o joga tem
# a sua variante (`ScheduleBattleMap`, ver MapBranch/MapSessionLayer). Faltavam
# os dois sentidos entre eles:
#   - PROMOVER: o que a mesa fez passa a ser o estado de fábrica;
#   - REPOR: a mesa volta ao estado de fábrica.
#
# ⚠️ CENÁRIO NÃO ENTRA AQUI, e não por esquecimento: objeto/terreno mexido numa
# sessão JÁ grava no mapa (MapSessionLayer#update! manda o cenário para o
# tabuleiro — "um objeto arrastado numa sessão muda o mapa para todas"). Só os
# campos de MESA divergem, e são esses que estes dois sentidos resolvem.
class MapVariant
  # O que a promoção leva da variante para o original.
  #
  # Fora ficam, a pedido: `tokens` (criaturas — os heróis e monstros são
  # daquela noite, não do tabuleiro) e `dropped_projectiles` (flecha no chão de
  # um combate que acabou).
  PROMOTE_FIELDS = %i[fog measurements drawings aoe_placements].freeze

  class << self
    # Variantes deste mapa, a mais recente primeiro, com o que a lista precisa
    # para o mestre escolher: mesa, data da sessão e o que a variante guarda.
    def list(map)
      ScheduleBattleMap
        .where(battle_map_id: map.id)
        .includes(schedule: %i[group date_dimension])
        .to_a
        .sort_by { |l| [l.schedule&.date_dimension&.date || Date.new(1900, 1, 1), l.schedule_id] }
        .reverse
        .map { |l| resumo(l, map) }
    end

    # A variante vira o estado de fábrica. Devolve os campos escritos.
    def promote!(map:, schedule_id:)
      link = buscar!(map, schedule_id)
      patch = PROMOTE_FIELDS.index_with { |f| link.public_send(f) }
      map.update!(patch)
      patch.keys
    end

    # A variante volta ao estado de fábrica (a mesma semente de uma mesa que
    # abre o mapa pela primeira vez — MapBranch.from_original).
    def reset!(map:, schedule_id:)
      link = buscar!(map, schedule_id)
      link.update!(MapBranch.from_original(map))
      link
    end

    private

    def buscar!(map, schedule_id)
      ScheduleBattleMap.find_by!(battle_map_id: map.id, schedule_id: schedule_id)
    end

    def resumo(link, map)
      sched = link.schedule
      {
        scheduleId: link.schedule_id,
        groupId: sched&.group_id,
        groupName: sched&.group&.name,
        sessionDate: sched&.date_dimension&.date&.iso8601,
        updatedAt: link.updated_at&.iso8601,
        creatureCount: Array(link.tokens).size,
        # "ainda igual ao original" é a informação que decide se vale promover:
        # sem ela o mestre teria de abrir cada mesa para descobrir.
        differsFromOriginal: difere?(link, map),
      }
    end

    def difere?(link, map)
      base = MapBranch.from_original(map)
      MapSessionLayer::SESSION_FIELDS.any? do |f|
        normaliza(link.public_send(f)) != normaliza(base[f])
      end
    end

    # jsonb volta com chaves string e nil/[] são o mesmo "vazio" aqui.
    def normaliza(v)
      return [] if v.nil?

      v
    end
  end
end
