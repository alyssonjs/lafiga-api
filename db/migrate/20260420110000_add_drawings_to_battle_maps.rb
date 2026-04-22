class AddDrawingsToBattleMaps < ActiveRecord::Migration[6.0]
  # Fase E4: lapis persistido. Cada drawing e um stroke:
  # { id, points: [{x,y}], color, widthPx, ownerUserId, createdAt }
  # x/y sao coordenadas DE GRADE em float (sub-celula) para suportar
  # desenho livre sem snapping. ownerUserId permite gating de remocao.
  def change
    add_column :battle_maps, :drawings, :jsonb, null: false, default: []
  end
end
