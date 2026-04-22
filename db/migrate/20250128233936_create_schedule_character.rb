class CreateScheduleCharacter < ActiveRecord::Migration[6.0]
  def change
    create_table :schedule_characters do |t|
      t.references :character, null: false, foreign_key: true
      t.references :schedule, null: false, foreign_key: true
      t.integer :status, default: 1, null: false
    end

    add_index :schedule_characters, [:character_id, :schedule_id], unique: true, name: 'idx_schedule_characters_unique_character_schedule'
  end
end
