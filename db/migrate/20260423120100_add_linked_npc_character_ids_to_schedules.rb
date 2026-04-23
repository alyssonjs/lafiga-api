# frozen_string_literal: true

class AddLinkedNpcCharacterIdsToSchedules < ActiveRecord::Migration[6.0]
  def change
    add_column :schedules, :linked_npc_character_ids, :jsonb, null: false, default: []
  end
end
