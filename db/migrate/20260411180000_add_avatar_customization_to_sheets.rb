# frozen_string_literal: true

# Persista chibi / avatar customization from character creation wizard (JSON).
class AddAvatarCustomizationToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :avatar_customization, :jsonb, default: {}, null: false
  end
end
