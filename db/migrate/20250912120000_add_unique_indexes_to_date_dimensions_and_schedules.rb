class AddUniqueIndexesToDateDimensionsAndSchedules < ActiveRecord::Migration[6.0]
  def change
    # Ensure each calendar date is unique
    add_index :date_dimensions, :date, unique: true, name: 'idx_date_dimensions_unique_date'

    # Enforce one schedule per calendar day (system-wide)
    # If the rule later changes to "one per group per day", replace with:
    # add_index :schedules, [:group_id, :date_dimension_id], unique: true, name: 'idx_schedules_unique_group_date'
    add_index :schedules, :date_dimension_id, unique: true, name: 'idx_schedules_unique_date_dimension'
  end
end

