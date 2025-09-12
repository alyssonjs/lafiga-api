class AddUniqueIndexToScheduleCharacters < ActiveRecord::Migration[6.0]
  def change
    add_index :schedule_characters, [:character_id, :schedule_id], unique: true, name: 'idx_schedule_characters_unique_character_schedule'
  end
end

