module Combat
  # Centraliza TODOS os broadcasts realtime do estado de combate. Os
  # controllers chamam o método correspondente após uma mutação bem-sucedida
  # (e.g. depois do `if combatant.save`), mantendo a lógica de transporte
  # fora do controller.
  #
  # Por que este wrapper (e não broadcast inline nos models via after_commit):
  #   - Alguns eventos derivados não cabem em uma única tabela (ex.: ao
  #     começar combate via StartService, queremos disparar `state_changed`
  #     UMA vez no fim, não vários eventos por combatant atualizado).
  #   - Mantém os models testáveis sem stub de ActionCable.
  #   - Permite suprimir broadcasts em fluxos batch (use `silently { ... }`).
  #
  # Shape canônico:
  #   { event: <string>, payload: <hash>, emitted_at: <iso8601> }
  module Broadcaster
    EVENTS = %w[
      state_changed
      combatant_upserted
      combatant_destroyed
      npc_upserted
      npc_destroyed
      log_appended
      concentration_broken
      session_meta_changed
    ].freeze

    module_function

    def state_changed(combat_state, command_id: nil, client_id: nil)
      return if suppressed? || combat_state.nil?
      broadcast(
        combat_state.schedule_id,
        'state_changed',
        Combat::Serializers.state(combat_state),
        command_id: command_id,
        client_id: client_id,
      )
    end

    def combatant_upserted(combatant, command_id: nil, client_id: nil)
      return if suppressed? || combatant.nil?
      broadcast(
        combatant.combat_state.schedule_id,
        'combatant_upserted',
        Combat::Serializers.combatant(combatant),
        command_id: command_id,
        client_id: client_id,
      )
    end

    def combatant_destroyed(schedule_id:, combatant_id:)
      return if suppressed?
      broadcast(schedule_id, 'combatant_destroyed', { id: combatant_id })
    end

    def npc_upserted(npc)
      return if suppressed? || npc.nil?
      broadcast(npc.schedule_id, 'npc_upserted', Combat::Serializers.npc(npc))
    end

    def npc_destroyed(schedule_id:, npc_id:)
      return if suppressed?
      broadcast(schedule_id, 'npc_destroyed', { id: npc_id })
    end

    def log_appended(log, command_id: nil, client_id: nil)
      return if suppressed? || log.nil?
      broadcast(
        log.schedule_id,
        'log_appended',
        Combat::Serializers.log(log),
        command_id: command_id,
        client_id: client_id,
      )
    end

    # Fase 6F — emitido após `record_concentration_save` quando o save falha.
    # Front pode usar para destacar visualmente a quebra (com som/animação)
    # antes do próximo `combatant_upserted` consolidar o estado.
    def concentration_broken(combatant, spell_name: nil, dc: nil)
      return if suppressed? || combatant.nil?
      broadcast(combatant.combat_state.schedule_id, 'concentration_broken', {
        combatant_id: combatant.id,
        spell: spell_name,
        dc: dc
      })
    end

    # Emitido pelo schedules_controller#update quando METADADOS da mesa mudam:
    # grupos/times de combate, NPCs de ficha vinculados e PJs marcados como
    # "NPC temporário". Diferente dos demais eventos (que carregam estado de
    # combate por combatant/npc), este sincroniza a CONFIGURAÇÃO da sessão para
    # todos os clientes com a mesa aberta — sem ele, mudar o time de um token ou
    # (des)vincular um NPC só aparecia após reload. Usa os MESMOS normalizadores
    # do ScheduleSerializer para o payload bater 1:1 com o load inicial.
    def session_meta_changed(schedule)
      return if suppressed? || schedule.nil?
      broadcast(schedule.id, 'session_meta_changed', {
        combat_groups: schedule.combat_groups_normalized,
        linked_npc_character_ids: schedule.linked_npc_sheet_ids_normalized,
        dm_temp_npc_character_ids: schedule.dm_temp_npc_character_ids_normalized,
        # Mapa ATIVO: o cliente troca de mapa (e reassina o MapChannel) por aqui.
        battle_map_id: schedule.battle_map_id,
      })
    end

    # Suprime broadcasts dentro do bloco. Usado em fluxos batch (StartService
    # atualizando N combatants HP de uma vez) para emitir um único
    # `state_changed` no final em vez de N eventos.
    #
    #   Combat::Broadcaster.silently do
    #     combatant.update!(...)
    #     combatant2.update!(...)
    #   end
    #   Combat::Broadcaster.state_changed(cs)
    def silently
      Thread.current[:combat_broadcaster_suppressed] = true
      yield
    ensure
      Thread.current[:combat_broadcaster_suppressed] = false
    end

    def suppressed?
      Thread.current[:combat_broadcaster_suppressed] == true
    end

    # Wrapper testável; specs podem substituir via stub.
    def broadcast(schedule_id, event, payload, command_id: nil, client_id: nil)
      event_id = SecureRandom.uuid
      envelope = {
        event: event,
        payload: payload,
        emitted_at: Time.current.iso8601,
        event_id: event_id,
      }
      safe_command_id = Realtime::Telemetry.identifier(command_id)
      safe_client_id = Realtime::Telemetry.identifier(client_id)
      envelope[:command_id] = safe_command_id if safe_command_id
      envelope[:client_id] = safe_client_id if safe_client_id

      ActionCable.server.broadcast(
        SessionRealtimeChannel.stream_name_for(schedule_id),
        envelope,
      )
      Realtime::Telemetry.emit(
        stage: 'event_broadcast',
        domain: 'combat',
        event_type: event,
        event_id: event_id,
        command_id: safe_command_id,
        client_id: safe_client_id,
        aggregate_type: 'schedule',
        aggregate_id: schedule_id,
        outcome: 'succeeded',
      )
      envelope
    end
  end
end
