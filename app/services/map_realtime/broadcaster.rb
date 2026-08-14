## MapRealtime::Broadcaster
##
## Wrapper fino sobre `ActionCable.server.broadcast` que centraliza os eventos
## emitidos para o MapChannel. Manter os tipos aqui evita "constantes magicas"
## espalhadas pelos controllers e facilita escrever specs.
##
## Eventos suportados (seguem o EVENTS hash):
##   - :token_moved      { tokenId, x, y, by_user_id }
##   - :tokens_patched   { additions, patches, deleteIds, version }
##   - :tokens_changed   { tokens: [...] }     # qualquer alteracao no array
##   - :token_equipment_changed { tokenId, chibiEquipment } # patch por campo
##   - :character_inventory_changed { characterId, sheetId } # invalidacao
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
      tokens_patched:       'tokens_patched',
      token_equipment_changed: 'token_equipment_changed',
      character_inventory_changed: 'character_inventory_changed',
      tokens_changed:       'tokens_changed',
      cells_changed:        'cells_changed',
      fog_changed:          'fog_changed',
      measurements_changed: 'measurements_changed',
      aoe_placements_changed: 'aoe_placements_changed',
      drawings_changed:     'drawings_changed',
      dropped_projectiles_changed: 'dropped_projectiles_changed',
      projectile_resolved:  'projectile_resolved',
      map_updated:          'map_updated',
      map_deleted:          'map_deleted'
    }.freeze

    class << self
      def broadcast(map_or_id, event, payload, actor: nil, command_id: nil, client_id: nil)
        type = EVENTS.fetch(event) { raise ArgumentError, "evento desconhecido: #{event.inspect}" }
        event_id = SecureRandom.uuid
        envelope = {
          event: type,
          payload: payload || {},
          actor_id: actor&.id,
          ts: Time.current.to_f,
          event_id: event_id,
        }

        safe_command_id = Realtime::Telemetry.identifier(command_id)
        safe_client_id = Realtime::Telemetry.identifier(client_id)
        envelope[:command_id] = safe_command_id if safe_command_id
        envelope[:client_id] = safe_client_id if safe_client_id

        ActionCable.server.broadcast(MapChannel.stream_name(map_or_id), envelope)
        Realtime::Telemetry.emit(
          stage: 'event_broadcast',
          domain: 'map',
          event_type: type,
          event_id: event_id,
          command_id: safe_command_id,
          client_id: safe_client_id,
          aggregate_type: 'battle_map',
          aggregate_id: map_or_id.respond_to?(:id) ? map_or_id.id : map_or_id,
          actor_id: actor&.id,
          outcome: 'succeeded',
        )
        envelope
      end

      def token_moved(map, token_id, x, y, actor: nil, command_id: nil, client_id: nil)
        broadcast(
          map,
          :token_moved,
          {
            tokenId: token_id,
            x: x,
            y: y,
            # O broadcast acontece depois que o row lock e liberado. Sob carga,
            # um movimento mais novo pode ser transmitido antes de um antigo.
            # A versao persistida permite ao cliente descartar esse evento tardio.
            version: (map.updated_at.to_f * 1_000_000).round,
          },
          actor: actor,
          command_id: command_id,
          client_id: client_id,
        )
      end

      def tokens_changed(map, tokens, actor: nil)
        broadcast(
          map,
          :tokens_changed,
          { tokens: tokens, version: persistence_version(map) },
          actor: actor,
        )
      end

      def tokens_patched(map, mutation, version:, actor: nil)
        patches = Array(mutation[:patches]).map do |patch|
          {
            tokenId: patch[:token_id],
            changes: patch[:changes],
            unset: patch[:unset],
          }
        end
        broadcast(
          map,
          :tokens_patched,
          {
            additions: mutation[:additions],
            patches: patches,
            deleteIds: mutation[:delete_ids],
            version: version,
          },
          actor: actor,
        )
      end

      def token_equipment_changed(map, token_id, chibi_equipment, actor: nil)
        broadcast(
          map,
          :token_equipment_changed,
          {
            tokenId: token_id,
            chibiEquipment: chibi_equipment,
            version: persistence_version(map),
          },
          actor: actor,
        )
      end

      def character_inventory_changed(map, character_id, sheet_id, actor: nil)
        broadcast(
          map,
          :character_inventory_changed,
          { characterId: character_id, sheetId: sheet_id },
          actor: actor,
        )
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

      def dropped_projectiles_changed(map, projectiles, actor: nil)
        broadcast(map, :dropped_projectiles_changed, { droppedProjectiles: projectiles }, actor: actor)
      end

      def projectile_resolved(map, projectile, actor: nil)
        broadcast(map, :projectile_resolved, { projectile: projectile }, actor: actor)
      end

      def map_updated(map, full_payload, actor: nil)
        broadcast(map, :map_updated, { battle_map: full_payload }, actor: actor)
      end

      def map_deleted(map_id, actor: nil)
        broadcast(map_id, :map_deleted, { id: map_id }, actor: actor)
      end

      private

      def persistence_version(map)
        (map.updated_at.to_f * 1_000_000).round
      end
    end
  end
end
