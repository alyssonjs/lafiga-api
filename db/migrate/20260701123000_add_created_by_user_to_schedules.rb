class AddCreatedByUserToSchedules < ActiveRecord::Migration[6.0]
  def up
    add_reference :schedules, :created_by_user, foreign_key: { to_table: :users }, index: true

    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_active_per_creator_date
      ON schedules (created_by_user_id, date_dimension_id)
      WHERE created_by_user_id IS NOT NULL AND status <> 4
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_schedules_active_per_creator_date"
    remove_reference :schedules, :created_by_user, foreign_key: { to_table: :users }, index: true
  end
end
