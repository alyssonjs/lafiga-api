class ReconcileScheduleOpenSlotIndexes < ActiveRecord::Migration[6.0]
  # Reconcilia os índices de "slot único" de agendamento entre as duas linhagens
  # que divergiram:
  #   - main (prod): idx_schedules_open_per_group / idx_schedules_open_per_creator_date
  #                  (status ∈ 0,1,2; SEM coluna sandbox)
  #   - epic:        idx_schedules_active_per_group_date / idx_schedules_active_per_creator_date
  #                  (status <> 4 AND sandbox = false; group_id+date)
  #
  # REGRA FINAL (escolhida): mantém o comportamento de PRODUÇÃO — 1 sessão ABERTA
  # por grupo (status ∈ 0,1,2, em qualquer data) — e passa a EXCLUIR sandbox.
  #
  # Defensiva: DROP INDEX IF EXISTS de TODOS os nomes das duas linhagens, depois
  # CREATE dos índices finais. Assim roda igual em qualquer estado do banco
  # (prod já tem os `open_*`; dev tem os `active_*`).
  def up
    execute 'DROP INDEX IF EXISTS idx_schedules_active_per_group_date'
    execute 'DROP INDEX IF EXISTS idx_schedules_active_per_creator_date'
    execute 'DROP INDEX IF EXISTS idx_schedules_open_per_group'
    execute 'DROP INDEX IF EXISTS idx_schedules_open_per_creator_date'

    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_schedules_open_per_group
      ON schedules (group_id)
      WHERE ((group_id IS NOT NULL) AND (status = ANY (ARRAY[0, 1, 2])) AND (sandbox = false))
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_schedules_open_per_creator_date
      ON schedules (created_by_user_id, date_dimension_id)
      WHERE ((created_by_user_id IS NOT NULL) AND (status = ANY (ARRAY[0, 1, 2])) AND (sandbox = false))
    SQL
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_schedules_open_per_group'
    execute 'DROP INDEX IF EXISTS idx_schedules_open_per_creator_date'
  end
end
