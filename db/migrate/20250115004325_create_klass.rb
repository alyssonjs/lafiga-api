class CreateKlass < ActiveRecord::Migration[6.0]
  def change
    create_table :klasses do |t|
      t.string :name
      t.string :api_index
      t.integer :hit_die
      t.string :spellcasting_ability
      t.integer :subclass_level
    end

    add_index :klasses, :api_index, unique: true
  end
end
