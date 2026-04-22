class CreateRaceTraits < ActiveRecord::Migration[6.0]
  def change
    create_table :race_traits do |t|
      t.references :race, null: false, foreign_key: true
      t.references :trait, null: false, foreign_key: true
      t.references :sub_race, foreign_key: true
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :race_traits, [:race_id, :trait_id, :sub_race_id], unique: true, name: 'idx_race_traits_unique'
  end
end
