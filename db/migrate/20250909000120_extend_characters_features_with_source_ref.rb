class ExtendCharactersFeaturesWithSourceRef < ActiveRecord::Migration[6.0]
  def change
    add_column :characters_features, :source_type, :string
    add_column :characters_features, :source_id, :bigint
    add_column :characters_features, :gained_at_level, :integer
    add_index  :characters_features, [:source_type, :source_id], name: 'idx_char_features_source'
  end
end

