class CreateJoinTableSubKlassLevelsFeatures < ActiveRecord::Migration[6.0]
  def change
    create_join_table :sub_klass_levels, :features do |t|
      t.index [:sub_klass_level_id, :feature_id], unique: true, name: 'idx_subklass_levels_features_unique'
      t.index :feature_id
    end
  end
end

