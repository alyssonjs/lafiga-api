class CreateFeats < ActiveRecord::Migration[6.0]
  def change
    create_table :feats do |t|
      t.string :name, null: false
      t.text :description
      t.text :prerequisites
      t.text :ability_bonuses
      t.text :proficiency_bonuses
      t.text :features
      t.string :api_index
      t.json :special_rules
      t.json :cantrips
      t.json :spells

      t.timestamps
    end

    add_index :feats, :name, unique: true
    add_index :feats, :api_index
  end
end
