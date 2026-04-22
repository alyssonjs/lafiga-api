class CreateDateDimension < ActiveRecord::Migration[6.0]
  def change
    create_table :date_dimensions do |t|
      t.date :date
      t.integer :year
      t.integer :month
      t.integer :day
      t.integer :day_of_week
      t.string :day_name
      t.boolean :is_weekend
      t.boolean :available

      t.timestamps
    end

    add_index :date_dimensions, :date, unique: true, name: 'idx_date_dimensions_unique_date'
  end
end
