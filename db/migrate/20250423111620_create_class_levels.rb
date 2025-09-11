class CreateClassLevels < ActiveRecord::Migration[6.0]
  def change
    create_table :class_levels do |t|
      t.references :klass, null: false, foreign_key: true
      t.integer :level
      t.integer :prof_bonus
      t.integer :ability_score_bonuses

      t.timestamps
    end
    add_index :class_levels, [:klass_id, :level], unique: true
  end
end
