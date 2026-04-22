class AddDistanceDisplayUnitToBattleMaps < ActiveRecord::Migration[6.0]
  # Unidade de distancia exibida no mapa (regua, AoE, etc.) — visivel a todos
  # os jogadores na sessao. Valores: ft | m. Default m (1 celula = 5ft = 1.5m).
  def change
    add_column :battle_maps, :distance_display_unit, :string, null: false, default: 'm'
  end
end
