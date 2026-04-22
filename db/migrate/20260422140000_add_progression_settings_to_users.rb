# frozen_string_literal: true

class AddProgressionSettingsToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :progression_settings, :jsonb, null: false, default: {}
  end
end
