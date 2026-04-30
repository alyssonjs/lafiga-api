# frozen_string_literal: true

class AddDmCustomizedToFeatures < ActiveRecord::Migration[6.0]
  def change
    add_column :features, :dm_customized, :boolean, null: false, default: false
    add_index :features, :dm_customized
  end
end
