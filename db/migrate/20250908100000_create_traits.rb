class CreateTraits < ActiveRecord::Migration[6.0]
  def change
    create_table :traits do |t|
      t.string :api_index, null: false
      t.string :name, null: false
      t.text   :description
      t.timestamps
    end
    add_index :traits, :api_index, unique: true
  end
end

