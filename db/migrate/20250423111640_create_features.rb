class CreateFeatures < ActiveRecord::Migration[6.0]
  def change
    create_table :features do |t|
      t.string :api_index, null: false
      t.string :name, null: false
      t.integer :category, default: 0, null: false
      t.text :description

      t.timestamps
    end

    add_index :features, :api_index, unique: true
  end
end
