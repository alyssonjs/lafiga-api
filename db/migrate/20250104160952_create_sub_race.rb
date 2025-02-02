class CreateSubRace < ActiveRecord::Migration[6.0]
  def change
    create_table :sub_races do |t|
      t.string :name
      t.references :race, foreign_key: true, null: false

      t.timestamps
    end
  end
end
