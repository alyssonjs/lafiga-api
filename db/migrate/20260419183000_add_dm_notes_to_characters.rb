# frozen_string_literal: true

class AddDmNotesToCharacters < ActiveRecord::Migration[6.0]
  def change
    add_column :characters, :dm_notes, :text
  end
end
