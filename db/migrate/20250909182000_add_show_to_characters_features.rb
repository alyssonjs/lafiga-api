class AddShowToCharactersFeatures < ActiveRecord::Migration[6.0]
  def change
    add_column :characters_features, :show, :boolean, null: false, default: true
    add_index  :characters_features, [:character_id, :feature_id, :show], name: 'idx_char_features_show'
  end
end

