class CreateSessionLogs < ActiveRecord::Migration[6.0]
  # Feed cronológico da sessão. É distinto de `messages` (chat) porque:
  # 1. Escopo é o Schedule (sessão), não um Channel (que pode atravessar
  #    múltiplas sessões e tem participantes diferentes).
  # 2. Tipo enumerado dirige render no front (cor, ícone, agrupamento).
  #    Chat é texto livre.
  # 3. `roll_result` é um payload estruturado (expression, total, breakdown)
  #    que o DM/players consultam ao reabrir a sessão.
  #
  # Campos:
  # - `kind`: enum (narrative=0, combat=1, roll=2, rest=3, note=4, xp=5).
  #   Mapeia 1:1 com `LogEntryType` do front (sessionData.ts).
  # - `actor`: string livre (nome do PC, NPC, "DM", "Sistema") — não FK porque
  #   pode ser entidade não-persistida (mensagem de sistema, NPC efêmero).
  # - `posted_at`: ordenação visual. `created_at` cobre persistência interna,
  #   mas `posted_at` permite backfill manual ou edição de timestamp pelo DM.
  #
  # Index `(schedule_id, posted_at DESC)` cobre a paginação reversa do feed
  # (mais recente primeiro).
  def change
    create_table :session_logs do |t|
      t.references :schedule, null: false, foreign_key: true

      t.integer  :kind,       default: 0, null: false
      t.string   :actor
      t.text     :message,    default: '', null: false
      t.jsonb    :roll_result  # nullable: a maioria dos logs não tem roll
      t.datetime :posted_at,  null: false

      t.timestamps
    end

    add_index :session_logs, [:schedule_id, :posted_at], order: { posted_at: :desc }, name: 'index_session_logs_on_schedule_and_posted_at_desc'
    add_index :session_logs, [:schedule_id, :kind]
  end
end
