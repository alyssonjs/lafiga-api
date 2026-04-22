# frozen_string_literal: true

class AddFogModeToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :fog_mode, :string, null: false, default: 'hidden_cells'
  end
end
