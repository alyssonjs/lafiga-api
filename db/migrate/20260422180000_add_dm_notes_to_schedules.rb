# frozen_string_literal: true

class AddDmNotesToSchedules < ActiveRecord::Migration[6.0]
  def change
    add_column :schedules, :dm_notes, :text
  end
end
