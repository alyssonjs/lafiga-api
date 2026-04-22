class RelaxScheduleDateUniqueness < ActiveRecord::Migration[6.0]
  # Permite múltiplas sessões no mesmo dia (entre grupos diferentes), mas garante
  # que UM mesmo grupo só pode ter UMA sessão ativa (não cancelada) por data.
  # Sessões canceladas liberam o slot e não contam no índice (partial unique).
  def up
    if index_exists?(:schedules, :date_dimension_id, name: "idx_schedules_unique_date_dimension")
      remove_index :schedules, name: "idx_schedules_unique_date_dimension"
    end

    # Cancelled é status=4 no enum (vide Schedule#enum). Usamos partial index
    # nativo do Postgres — Rails 6.0 não suporta `where:` em add_index do mesmo
    # modo confortável, então usamos SQL puro para garantir o filtro correto.
    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_active_per_group_date
      ON schedules (group_id, date_dimension_id)
      WHERE group_id IS NOT NULL AND status <> 4
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_schedules_active_per_group_date"
    add_index :schedules, :date_dimension_id,
              unique: true,
              name: "idx_schedules_unique_date_dimension"
  end
end
