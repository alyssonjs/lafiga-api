class CreateSpells < ActiveRecord::Migration[6.0]
  def change
    create_table :spells do |t|
      t.string  :api_index,       null: false
      t.string  :name,            null: false
      t.integer :level
      t.string  :school
      t.string  :range
      t.text    :components
      t.text    :material
      t.boolean :ritual
      t.string  :duration
      t.boolean :concentration
      t.string  :casting_time
      t.text    :desc
      t.text    :higher_level

      t.timestamps
    end
    add_index :spells, :api_index, unique: true
  end
end
