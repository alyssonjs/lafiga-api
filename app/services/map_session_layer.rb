# frozen_string_literal: true

# Onde vive o estado de MESA de um mapa.
#
# O mapa e um TABULEIRO reutilizavel (fundo, paredes, terreno, cenario). Tokens
# de criatura, nevoa, medidas, desenhos, AoE e projeteis sao de cada sessao — se
# ficassem no mapa, duas mesas no mesmo mapa veriam as pecas (e a nevoa) uma da
# outra.
#
# Este objeto e o DESTINO de leitura/escrita desse estado. Com sessao, aponta
# para o `ScheduleBattleMap`; sem sessao (Map Builder, mapa sem vinculo), aponta
# para o proprio mapa — assim os chamadores nao precisam de `if sessao` e o
# comportamento antigo continua valendo onde nao ha mesa.
class MapSessionLayer
  SESSION_FIELDS = %i[tokens fog measurements drawings aoe_placements dropped_projectiles].freeze

  # @return [MapSessionLayer]
  def self.for(map:, schedule_id: nil)
    link =
      if map && schedule_id.present?
        ScheduleBattleMap.find_by(schedule_id: schedule_id, battle_map_id: map.id)
      end

    new(map: map, link: link)
  end

  attr_reader :map, :link

  def initialize(map:, link: nil)
    @map = map
    @link = link
  end

  # `true` quando o estado de mesa esta isolado por sessao.
  def session_scoped?
    link.present?
  end

  # Alvo dos campos de mesa: a linha do vinculo ou o proprio mapa.
  def target
    link || map
  end

  # Tokens visiveis: cenario do mapa + criaturas da mesa. Sem sessao, o mapa
  # responde inteiro (e o que o Map Builder edita).
  def tokens
    return Array(map&.tokens) unless session_scoped?

    map.scenery_tokens + Array(link.tokens)
  end

  SESSION_FIELDS.each do |field|
    next if field == :tokens

    define_method(field) { target.public_send(field) }
  end

  # Grava so os campos de mesa. Ao gravar `tokens` com sessao, o CENARIO e
  # separado de volta para o mapa — o chamador manda a lista completa que viu.
  def update!(attrs)
    attrs = attrs.symbolize_keys
    unknown = attrs.keys - SESSION_FIELDS
    raise ArgumentError, "campo fora da camada de mesa: #{unknown.inspect}" if unknown.any?

    return target.update!(attrs) unless session_scoped?

    if attrs.key?(:tokens)
      todos = Array(attrs[:tokens])
      cenario = todos.select { |t| BattleMap.scenery_token?(t) }
      attrs[:tokens] = todos.select { |t| BattleMap.creature_token?(t) }
      # O cenario continua sendo do tabuleiro: um objeto arrastado numa sessao
      # muda o mapa para todas (e o comportamento esperado de cenario).
      map.update!(tokens: cenario) if cenario != map.scenery_tokens
    end

    link.update!(attrs)
  end
end
