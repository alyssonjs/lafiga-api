# frozen_string_literal: true

module SessionFeed
  # Persistência idempotente de items do SessionFeedChannel.
  #
  # Regras (espelham o `ingestFeedItem` do front em useDiceRollFeed.ts):
  # 1. Dedup por (schedule_id, client_id) — garante que retries de broadcast
  #    não dupliquem registros.
  # 2. Quando chega um `roll` com `rollGroupId`, **substitui** o `roll_pending`
  #    correspondente (mesma posição lógica no feed; mesmo timestamp original).
  # 3. Quando chega `attack_hit_resolution`, **atualiza** o roll original
  #    (campo attackHitOutcome no payload), em vez de criar registro novo.
  #
  # Safety net: 1 a cada SAFETY_NET_RATE inserts dispara Retention inline
  # para garantir cleanup mesmo sem cron rodando.
  class Persist
    SAFETY_NET_RATE = 100

    class << self
      # Persiste um item normalizado vindo do channel.
      # Retorna SessionFeedItem ou nil em caso de payload inválido.
      def call(schedule_id:, normalized:)
        return nil if schedule_id.blank?
        return nil unless normalized.is_a?(Hash)
        return nil unless SessionFeedItem::KINDS.include?(normalized['kind'])

        case normalized['kind']
        when 'attack_hit_resolution'
          apply_attack_hit_resolution(schedule_id, normalized)
        when 'roll'
          upsert_roll(schedule_id, normalized)
        else
          create_simple(schedule_id, normalized)
        end
      end

      # Marca de forma duravel o card de TR correspondente. O evento realtime
      # continua sendo emitido pelo controller, mas um reload tambem deve trazer
      # `savePrompt.resolved=true` do historico.
      def resolve_save_prompt(schedule_id:, roll_group_id:)
        return nil if schedule_id.blank? || roll_group_id.blank?

        roll = SessionFeedItem.where(
          schedule_id: schedule_id,
          kind: 'roll',
          roll_group_id: roll_group_id,
        ).first
        return nil unless roll

        roll.with_lock do
          roll.reload
          prompt = roll.payload['savePrompt']
          next unless prompt.is_a?(Hash)
          next if ActiveModel::Type::Boolean.new.cast(prompt['resolved'])

          roll.update!(payload: roll.payload.merge(
            'savePrompt' => prompt.merge('resolved' => true),
          ))
        end
        roll
      end

      private

      def timestamp_to_time(ms_or_s)
        return Time.current if ms_or_s.blank?
        n = ms_or_s.to_i
        # Heurística: timestamps em ms (>= ano 2001 em ms é >= 1e12).
        n >= 1_000_000_000_000 ? Time.at(n / 1000.0) : Time.at(n)
      rescue StandardError
        Time.current
      end

      def attrs_for(schedule_id, normalized)
        {
          schedule_id:    schedule_id,
          kind:           normalized['kind'],
          client_id:      normalized['id'],
          roll_group_id:  normalized['rollGroupId'].presence,
          payload:        normalized,
          posted_at:      timestamp_to_time(normalized['timestamp']),
        }
      end

      def create_simple(schedule_id, normalized)
        item = SessionFeedItem.find_or_initialize_by(
          schedule_id: schedule_id,
          client_id:   normalized['id'],
        )
        # Retries HTTP/ActionCable recebem a primeira resposta confirmada. Um
        # snapshot atrasado nunca pode trocar o resultado da mesma rolagem.
        return item if item.persisted?

        item.assign_attributes(attrs_for(schedule_id, normalized))
        item.save!
        trigger_safety_net_cleanup(schedule_id)
        item
      rescue ActiveRecord::RecordNotUnique
        # Race entre clients/retries — tudo bem, item já existe.
        SessionFeedItem.find_by(schedule_id: schedule_id, client_id: normalized['id'])
      end

      # `roll` com rollGroupId substitui `roll_pending` correspondente.
      # Preserva o `posted_at` original do pending para manter posição cronológica
      # (espelha a substituição in-place no front).
      def upsert_roll(schedule_id, normalized)
        rg = normalized['rollGroupId'].presence
        ActiveRecord::Base.transaction do
          if rg
            pending = SessionFeedItem.where(
              schedule_id: schedule_id,
              kind: 'roll_pending',
              roll_group_id: rg,
            ).lock.first
            if pending
              merged = attrs_for(schedule_id, normalized).merge(posted_at: pending.posted_at)
              pending.assign_attributes(merged)
              pending.save!
              trigger_safety_net_cleanup(schedule_id)
              return pending
            end
          end
          create_simple(schedule_id, normalized)
        end
      end

      # `attack_hit_resolution` atualiza o roll de attack correspondente in-place.
      def apply_attack_hit_resolution(schedule_id, normalized)
        rg = normalized['rollGroupId'].presence
        return nil unless rg
        outcome = normalized['outcome']
        return nil unless %w[hit miss].include?(outcome)

        roll = SessionFeedItem.where(schedule_id: schedule_id, kind: 'roll', roll_group_id: rg).first
        return nil unless roll

        roll.with_lock do
          roll.reload
          # First-write-wins: duas abas do Mestre podem repetir a confirmação,
          # mas uma mensagem atrasada não inverte um resultado já finalizado.
          next if %w[hit miss].include?(roll.payload['attackHitOutcome'])

          new_payload = roll.payload.merge('attackHitOutcome' => outcome)
          roll.update!(payload: new_payload)
        end
        roll
      end

      def trigger_safety_net_cleanup(schedule_id)
        return unless rand(SAFETY_NET_RATE).zero?
        SessionFeed::Retention.call(schedule_id: schedule_id)
      rescue StandardError => e
        Rails.logger.warn(
          { event: 'session_feed.persist_safety_net_cleanup_failed',
            schedule_id: schedule_id, error: e.class.name, message: e.message }.to_json,
        )
      end
    end
  end
end
