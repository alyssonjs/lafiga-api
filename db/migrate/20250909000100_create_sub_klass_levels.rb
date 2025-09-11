class CreateSubKlassLevels < ActiveRecord::Migration[6.0]
  def change
    create_table :sub_klass_levels do |t|
      t.references :sub_klass, null: false, foreign_key: true
      t.integer :level, null: false
      t.timestamps
    end
    add_index :sub_klass_levels, [:sub_klass_id, :level], unique: true
  end
end

