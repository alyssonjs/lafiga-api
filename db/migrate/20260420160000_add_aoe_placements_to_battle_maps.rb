class AddAoePlacementsToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :aoe_placements, :jsonb, null: false, default: []
  end
end
