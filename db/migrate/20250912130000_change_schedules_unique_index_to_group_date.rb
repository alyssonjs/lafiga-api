class ChangeSchedulesUniqueIndexToGroupDate < ActiveRecord::Migration[6.0]
  def up
    if index_exists?(:schedules, :date_dimension_id, name: 'idx_schedules_unique_date_dimension', unique: true)
      remove_index :schedules, name: 'idx_schedules_unique_date_dimension'
    end

    unless index_exists?(:schedules, [:group_id, :date_dimension_id], name: 'idx_schedules_unique_group_date', unique: true)
      add_index :schedules, [:group_id, :date_dimension_id], unique: true, name: 'idx_schedules_unique_group_date'
    end
  end

  def down
    if index_exists?(:schedules, [:group_id, :date_dimension_id], name: 'idx_schedules_unique_group_date', unique: true)
      remove_index :schedules, name: 'idx_schedules_unique_group_date'
    end

    unless index_exists?(:schedules, :date_dimension_id, name: 'idx_schedules_unique_date_dimension', unique: true)
      add_index :schedules, :date_dimension_id, unique: true, name: 'idx_schedules_unique_date_dimension'
    end
  end
end

