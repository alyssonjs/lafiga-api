class AddMeasurementsToBattleMaps < ActiveRecord::Migration[6.0]
  # Fase E3: regua persistida. Cada medida e um hash:
  # { id, points: [{x,y}], totalFt, color, label?, ownerUserId, createdAt }
  # ownerUserId permite limitar remocao a autor/DM no controller.
  def change
    add_column :battle_maps, :measurements, :jsonb, null: false, default: []
  end
end
