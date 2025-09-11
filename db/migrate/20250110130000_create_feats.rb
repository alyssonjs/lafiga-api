class CreateFeats < ActiveRecord::Migration[6.0]
  def change
    create_table :feats do |t|
      t.string :name, null: false
      t.text :description
      t.text :prerequisites # JSON string
      t.text :ability_bonuses # JSON string
      t.text :proficiency_bonuses # JSON string
      t.text :features # JSON string
      t.string :api_index # For D&D 5e API reference
      t.timestamps
    end

    add_index :feats, :name, unique: true
    add_index :feats, :api_index
  end
end
