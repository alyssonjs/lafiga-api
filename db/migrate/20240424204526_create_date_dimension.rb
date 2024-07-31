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
  end
end
