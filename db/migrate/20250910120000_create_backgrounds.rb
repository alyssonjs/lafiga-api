class CreateBackgrounds < ActiveRecord::Migration[6.0]
  def change
    create_table :backgrounds do |t|
      t.string :api_index, null: false
      t.string :name, null: false
      t.string :feature_name
      t.text :feature_desc
      t.text :data_json

      t.timestamps
    end
    add_index :backgrounds, :api_index, unique: true
  end
end

