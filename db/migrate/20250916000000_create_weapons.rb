class CreateWeapons < ActiveRecord::Migration[6.0]
  def change
    create_table :weapons do |t|
      t.string :api_index, null: false
      t.string :name, null: false
      t.string :category
      t.string :range_type
      t.integer :hands
      t.string :damage_die
      t.string :versatile_die
      t.string :range
      t.jsonb :properties, default: []

      t.timestamps
    end

    add_index :weapons, :api_index, unique: true
    add_index :weapons, :category
    add_index :weapons, :range_type
  end
end
