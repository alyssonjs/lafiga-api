# frozen_string_literal: true

class AddPlayableToRacesAndSubRaces < ActiveRecord::Migration[6.0]
  def change
    add_column :races, :playable, :boolean, null: false, default: true
    add_column :sub_races, :playable, :boolean, null: false, default: true

    add_index :races, :playable
    add_index :sub_races, :playable
  end
end
