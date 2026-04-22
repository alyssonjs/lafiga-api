class CreateSchedules < ActiveRecord::Migration[6.0]
  def change
    create_table :schedules do |t|
      t.integer :status, default: 1, null: false
      t.references :date_dimension, null: false, foreign_key: true, index: false
      t.references :group, foreign_key: true
      t.string :title, null: false

      t.timestamps
    end

    add_index :schedules, :date_dimension_id, unique: true, name: 'idx_schedules_unique_date_dimension'
  end
end
