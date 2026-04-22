class CreateSubKlass < ActiveRecord::Migration[6.0]
  def change
    create_table :sub_klasses do |t|
      t.string :name
      t.references :klass, null: false, foreign_key: true
      t.string :api_index
      t.string :subclass_flavor
      t.text :description
      t.text :levels_json
    end

    add_index :sub_klasses, :api_index
    add_index :sub_klasses, [:klass_id, :api_index], unique: true, name: 'idx_sub_klasses_unique_klass_api'
  end
end
