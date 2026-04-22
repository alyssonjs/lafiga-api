## MapRealtime::Broadcaster
##
## Wrapper fino sobre `ActionCable.server.broadcast` que centraliza os eventos
## emitidos para o MapChannel. Manter os tipos aqui evita "constantes magicas"
## espalhadas pelos controllers e facilita escrever specs.
##
## Eventos suportados (seguem o EVENTS hash):
##   - :token_moved      { tokenId, x, y, by_user_id }
##   - :tokens_changed   { tokens: [...] }     # qualquer alteracao no array
##   - :cells_changed    { cells: [[..]] }     # full matrix (debounced no client)
##   - :fog_changed      { fog: [[..]] }
##   - :map_updated      { battle_map: <full payload> }
##   - :map_deleted      { id }
##
## Cada broadcast carrega `event` (string), `payload` (hash) e `actor_id`
## (id do usuario que originou — para o front skipar echo).
module MapRealtime
  class Broadcaster
    EVENTS = {
      token_moved:          'token_moved',
      tokens_changed:       'tokens_changed',
      cells_changed:        'cells_changed',
      fog_changed:          'fog_changed',
      measurements_changed: 'measurements_changed',
      aoe_placements_changed: 'aoe_placements_changed',
      drawings_changed:     'drawings_changed',
      map_updated:          'map_updated',
      map_deleted:          'map_deleted'
    }.freeze

    class << self
      def broadcast(map_or_id, event, payload, actor: nil)
        type = EVENTS.fetch(event) { raise ArgumentError, "evento desconhecido: #{event.inspect}" }
        ActionCable.server.broadcast(
          MapChannel.stream_name(map_or_id),
          {
            event: type,
            payload: payload || {},
            actor_id: actor&.id,
            ts: Time.current.to_f
          }
        )
      end

      def token_moved(map, token_id, x, y, actor: nil)
        broadcast(map, :token_moved, { tokenId: token_id, x: x, y: y }, actor: actor)
      end

      def tokens_changed(map, tokens, actor: nil)
        broadcast(map, :tokens_changed, { tokens: tokens }, actor: actor)
      end

      def cells_changed(map, cells, actor: nil)
        broadcast(map, :cells_changed, { cells: cells }, actor: actor)
      end

      def fog_changed(map, fog, actor: nil)
        broadcast(map, :fog_changed, { fog: fog }, actor: actor)
      end

      def measurements_changed(map, measurements, actor: nil)
        broadcast(map, :measurements_changed, { measurements: measurements }, actor: actor)
      end

      def aoe_placements_changed(map, aoe_placements, actor: nil)
        broadcast(map, :aoe_placements_changed, { aoePlacements: aoe_placements }, actor: actor)
      end

      def drawings_changed(map, drawings, actor: nil)
        broadcast(map, :drawings_changed, { drawings: drawings }, actor: actor)
      end

      def map_updated(map, full_payload, actor: nil)
        broadcast(map, :map_updated, { battle_map: full_payload }, actor: actor)
      end

      def map_deleted(map_id, actor: nil)
        broadcast(map_id, :map_deleted, { id: map_id }, actor: actor)
      end
    end
  end
end
