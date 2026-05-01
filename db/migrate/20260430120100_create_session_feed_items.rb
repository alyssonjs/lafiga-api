class CreateSessionFeedItems < ActiveRecord::Migration[6.0]
  # Persistência do feed da sessão (chat + dice rolls). Distinto de `session_logs`:
  # - session_logs: feed cronológico estruturado (kind enumerado, render por tipo).
  # - session_feed_items: o que passa pelo SessionFeedChannel (chat livre + rolls
  #   com schemas fluidos: gif/sticker, rollGroupId, attackHitOutcome, etc.).
  #   Alimenta o histórico do DiceRollBubble (chat lateral) entre conexões.
  #
  # Política de retenção (SessionFeed::Retention):
  # - Hard delete diário via cron (whenever) + safety-net inline (1/100 inserts).
  # - Critério: items com `posted_at < 1 mês` E não pertencentes às últimas 1000
  #   do schedule são removidos. Canais com pouco volume preservam tudo.
  # - `roll_pending` é efêmero (TTL ~2min no front); persistimos para handoff
  #   entre devices, mas o cleanup também derruba pendings >5min.
  #
  # Campos:
  # - `kind`: chat | roll | roll_pending | attack_hit_resolution.
  # - `client_id`: id gerado pelo cliente (`msg-...`, `roll-...`, `ahr-...`).
  #   Único por schedule — garante idempotência em retries de broadcast.
  # - `roll_group_id`: agrupa roll_pending → roll → attack_hit_resolution.
  # - `payload`: jsonb com o item já normalizado (mesmo formato do broadcast).
  # - `posted_at`: timestamp do cliente (ms convertido em datetime), usado para
  #   ordenação cronológica + critério de retenção.
  #
  # Índices:
  # - (schedule_id, posted_at DESC) cobre paginação reversa.
  # - (schedule_id, client_id) único garante dedup.
  # - (schedule_id, roll_group_id) acelera lookup de pending → roll.
  def change
    create_table :session_feed_items do |t|
      t.references :schedule, null: false, foreign_key: true

      t.string   :kind,          null: false
      t.string   :client_id,     null: false
      t.string   :roll_group_id
      t.jsonb    :payload,       null: false, default: {}
      t.datetime :posted_at,     null: false

      t.timestamps
    end

    add_index :session_feed_items,
              [:schedule_id, :posted_at],
              order: { posted_at: :desc },
              name: 'index_session_feed_items_on_schedule_and_posted_at_desc'

    add_index :session_feed_items,
              [:schedule_id, :client_id],
              unique: true,
              name: 'index_session_feed_items_on_schedule_and_client_id_uniq'

    add_index :session_feed_items,
              [:schedule_id, :roll_group_id],
              where: 'roll_group_id IS NOT NULL',
              name: 'index_session_feed_items_on_schedule_and_roll_group_id'
  end
end
