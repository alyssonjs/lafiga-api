class CreateJoinTableClassLevelsFeatures < ActiveRecord::Migration[6.0]
  def change
    create_join_table :class_levels, :features do |t|
      t.index [:class_level_id, :feature_id], unique: true, name: 'index_class_levels_features_on_class_level_and_feature'
      t.index :feature_id
    end
  end
end
