class CreateSheet < ActiveRecord::Migration[6.0]
  def change
    create_table :sheets do |t|
      t.references :character, foreign_key: true, null: false, unique: true
      t.references :sub_race, foreign_key: true, null: true
      t.references :race, foreign_key: true, null: false
    end
  end
end