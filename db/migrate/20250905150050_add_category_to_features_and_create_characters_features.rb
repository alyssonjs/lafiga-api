class AddCategoryToFeaturesAndCreateCharactersFeatures < ActiveRecord::Migration[6.0]
  def change
    add_column :features, :category, :integer, default: 0, null: false

    create_table :characters_features do |t|
      t.bigint :character_id, null: false
      t.bigint :feature_id,   null: false
      t.string :source
      t.integer :level
      t.timestamps
    end
    add_index :characters_features, [:character_id, :feature_id], unique: true, name: 'idx_char_features_unique'
    add_foreign_key :characters_features, :characters
    add_foreign_key :characters_features, :features
  end
end

