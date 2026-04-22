# frozen_string_literal: true

class CreateCharacterDmLevelUnlocks < ActiveRecord::Migration[6.0]
  def change
    create_table :character_dm_level_unlocks do |t|
      t.references :character, null: false, foreign_key: true, index: { unique: true }
      t.references :unlocked_by_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
