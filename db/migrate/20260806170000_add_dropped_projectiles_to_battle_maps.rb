# frozen_string_literal: true

class AddDroppedProjectilesToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :dropped_projectiles, :jsonb, null: false, default: []
  end
end
