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
    ].freeze

    module_function

    def state_changed(combat_state)
      return if suppressed? || combat_state.nil?
      broadcast(combat_state.schedule_id, 'state_changed', Combat::Serializers.state(combat_state))
    end

    def combatant_upserted(combatant)
      return if suppressed? || combatant.nil?
      broadcast(combatant.combat_state.schedule_id, 'combatant_upserted', Combat::Serializers.combatant(combatant))
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

    def log_appended(log)
      return if suppressed? || log.nil?
      broadcast(log.schedule_id, 'log_appended', Combat::Serializers.log(log))
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
    def broadcast(schedule_id, event, payload)
      ActionCable.server.broadcast(
        SessionRealtimeChannel.stream_name_for(schedule_id),
        { event: event, payload: payload, emitted_at: Time.current.iso8601 },
      )
    end
  end
end
