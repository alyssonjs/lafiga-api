class EnforceOpenScheduleUniquenessByGroup < ActiveRecord::Migration[6.0]
  OPEN_STATUSES = [0, 1, 2].freeze # reserved, waiting, in_progress

  def up
    execute "DROP INDEX IF EXISTS idx_schedules_active_per_group_date"
    execute "DROP INDEX IF EXISTS idx_schedules_active_per_creator_date"

    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_open_per_group
      ON schedules (group_id)
      WHERE group_id IS NOT NULL AND status IN (#{OPEN_STATUSES.join(',')})
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_open_per_creator_date
      ON schedules (created_by_user_id, date_dimension_id)
      WHERE created_by_user_id IS NOT NULL AND status IN (#{OPEN_STATUSES.join(',')})
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_schedules_open_per_group"
    execute "DROP INDEX IF EXISTS idx_schedules_open_per_creator_date"

    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_active_per_group_date
      ON schedules (group_id, date_dimension_id)
      WHERE group_id IS NOT NULL AND status <> 4
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS idx_schedules_active_per_creator_date
      ON schedules (created_by_user_id, date_dimension_id)
      WHERE created_by_user_id IS NOT NULL AND status <> 4
    SQL
  end
end
