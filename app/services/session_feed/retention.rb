# frozen_string_literal: true

module SessionFeed
  # Política de retenção do session_feed_items.
  #
  # Regra: items com `posted_at < AGE_THRESHOLD` são deletados *exceto* quando
  # estão entre os `KEEP_LATEST` mais recentes do schedule. Isto preserva o
  # histórico de canais com pouco volume, mas evita inflar o banco em mesas
  # ativas (chat com mídia/sticker pode crescer rápido).
  #
  # Adicionalmente, `roll_pending` órfãos (>5min) são removidos sempre — são
  # efêmeros por natureza (TTL de 2min no front, deixamos folga para clock skew).
  #
  # Trigger:
  # - Cron diário via `whenever` (config/schedule.rb) — `SessionFeed::Retention.run_all`.
  # - Safety-net inline em `Persist` (1 a cada 100 inserts).
  class Retention
    AGE_THRESHOLD = 1.month
    KEEP_LATEST = 1_000
    PENDING_TTL = 5.minutes

    class << self
      # Roda retenção em todos os schedules que têm session_feed_items.
      # Usado pelo cron job. Retorna número total de items removidos.
      def run_all
        total = 0
        SessionFeedItem.distinct.pluck(:schedule_id).each do |sid|
          total += call(schedule_id: sid)
        end
        Rails.logger.info({ event: 'session_feed.retention.run_all', deleted: total }.to_json)
        total
      end

      # Retém o feed de um schedule específico. Retorna número de items deletados.
      def call(schedule_id:)
        return 0 if schedule_id.blank?

        deleted = 0
        deleted += prune_old_items(schedule_id)
        deleted += prune_stale_pending(schedule_id)

        if deleted.positive?
          Rails.logger.info(
            { event: 'session_feed.retention.pruned',
              schedule_id: schedule_id, deleted: deleted }.to_json,
          )
        end

        deleted
      end

      private

      # Remove items com posted_at < AGE_THRESHOLD que NÃO estão entre os
      # KEEP_LATEST mais recentes do schedule.
      def prune_old_items(schedule_id)
        threshold = AGE_THRESHOLD.ago

        # IDs dos KEEP_LATEST mais recentes (preservados independente da idade).
        keep_ids = SessionFeedItem
                    .where(schedule_id: schedule_id)
                    .recent_first
                    .limit(KEEP_LATEST)
                    .pluck(:id)

        scope = SessionFeedItem.where(schedule_id: schedule_id).where('posted_at < ?', threshold)
        scope = scope.where.not(id: keep_ids) if keep_ids.any?
        scope.delete_all
      end

      # Pendings órfãos: tinham que ter virado `roll` em segundos. Limpamos
      # os que ficaram >5min para evitar lixo (cliente desconectou no meio).
      def prune_stale_pending(schedule_id)
        SessionFeedItem
          .where(schedule_id: schedule_id, kind: 'roll_pending')
          .where('posted_at < ?', PENDING_TTL.ago)
          .delete_all
      end
    end
  end
end
