# frozen_string_literal: true

## Sheets::Runtime::Broadcaster
##
## Avisa a mesa quando o runtime de uma ficha muda (recursos de classe, espaços
## de magia, condições, descansos).
##
## Por que existe: até 18/08 o PATCH de runtime era MUDO. O cliente que mutava
## atualizava sozinho (merge otimista) e o `BroadcastChannel` do front cobria
## outras ABAS do mesmo navegador — nunca outro dispositivo. Na mesa: o Mestre
## tirava usos de Inspiração Bárdica e o jogador, no celular, continuava vendo
## os pontos cheios até recarregar.
##
## Vai pelo MESMO stream do combate (`SessionRealtimeChannel`), porque quem
## precisa ver já está inscrito nele: os participantes daquela sessão.
##
## Evento: `sheet_runtime_changed`
## Payload: { sheet_id, character_id, runtime_state }
module Sheets
  module Runtime
    class Broadcaster
      EVENT = 'sheet_runtime_changed'

      class << self
        # `schedule_id` explícito ganha da derivação: cobre a ficha-NPC do
        # Mestre, que é vinculada pela sessão (metadata) e não por
        # `schedule_characters`.
        def broadcast_change(sheet, runtime, schedule_id: nil, actor: nil)
          return if sheet.nil? || runtime.nil?

          payload = {
            sheet_id: sheet.id,
            character_id: sheet.character_id,
            runtime_state: runtime.as_payload
          }

          schedule_ids_for(sheet, schedule_id).each do |sid|
            emit(sid, payload, actor: actor)
          end
        end

        private

        # Sem alvo nenhum o broadcast é no-op — mutar a ficha fora de uma sessão
        # não precisa acordar mesa alguma.
        def schedule_ids_for(sheet, explicit_id)
          return [explicit_id.to_i] if explicit_id.present?
          return [] if sheet.character_id.blank?

          Schedule
            .joins(:schedule_characters)
            .where(schedule_characters: { character_id: sheet.character_id })
            .distinct
            .pluck(:id)
        end

        def emit(schedule_id, payload, actor: nil)
          envelope = {
            event: EVENT,
            payload: payload,
            emitted_at: Time.current.iso8601,
            event_id: SecureRandom.uuid,
            actor_id: actor&.id
          }
          ActionCable.server.broadcast(
            SessionRealtimeChannel.stream_name_for(schedule_id),
            envelope
          )
          envelope
        rescue StandardError => e
          # Tempo real é MELHORIA, não pré-requisito: o PATCH já persistiu. Uma
          # falha aqui não pode derrubar a mutação do jogador.
          Rails.logger.error("[Sheets::Runtime::Broadcaster] #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
