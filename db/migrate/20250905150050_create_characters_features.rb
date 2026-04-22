class CreateCharactersFeatures < ActiveRecord::Migration[6.0]
  def change
    create_table :characters_features do |t|
      t.references :character, null: false, foreign_key: true
      t.references :feature, null: false, foreign_key: true
      t.string :source
      t.integer :level
      t.string :source_type
      t.bigint :source_id
      t.integer :gained_at_level
      t.boolean :show, default: true, null: false

      t.timestamps
    end

    add_index :characters_features, [:character_id, :feature_id], unique: true, name: 'idx_char_features_unique'
    add_index :characters_features, [:character_id, :feature_id, :show], name: 'idx_char_features_show'
    add_index :characters_features, [:source_type, :source_id], name: 'idx_char_features_source'
  end
end
