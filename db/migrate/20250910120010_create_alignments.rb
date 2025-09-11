class CreateAlignments < ActiveRecord::Migration[6.0]
  def change
    create_table :alignments do |t|
      t.string :api_index, null: false
      t.string :name, null: false
      t.string :abbreviation
      t.text :desc

      t.timestamps
    end
    add_index :alignments, :api_index, unique: true
  end
end

