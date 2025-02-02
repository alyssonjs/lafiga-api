class CreateScheduleCharacter < ActiveRecord::Migration[6.0]
  def change
    create_table :schedule_characters do |t|
      t.references :character, foreign_key: true, null: false, unique: true
      t.references :schedule, foreign_key: true, null: false
      t.integer :status, default: 1, null: false
    end
  end
end
