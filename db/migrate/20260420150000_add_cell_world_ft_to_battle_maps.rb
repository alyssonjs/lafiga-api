class AddCellWorldFtToBattleMaps < ActiveRecord::Migration[6.0]
  # Tamanho de cada quadrícula no mundo (pés de jogo). Padrão 5 ft = 1,5 m por
  # célula (D&D). Múltiplos de 5 ft <=> múltiplos de 1,5 m.
  def change
    add_column :battle_maps, :cell_world_ft, :decimal, precision: 6, scale: 2, null: false, default: 5.0
  end
end
