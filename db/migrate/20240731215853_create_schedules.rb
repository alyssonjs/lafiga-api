class CreateSchedules < ActiveRecord::Migration[6.0]
  def change
    create_table :schedules do |t|
      t.integer :status, default: 1, null: false
      t.references :date_dimension, foreign_key: true, null: false
      t.integer :group_id, null: false
      t.string :title, null: false

      t.timestamps
    end
  end
end