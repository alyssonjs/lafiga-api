class AddPlayerPermissionsToBattleMaps < ActiveRecord::Migration[6.0]
  # Fase E5: gating de ferramentas para players (DM sempre pode tudo).
  # Estrutura: { "measure" => true, "pencil" => false }
  # Default conservador: players podem medir mas nao desenhar.
  def change
    add_column :battle_maps, :player_permissions, :jsonb, null: false,
               default: { measure: true, pencil: false }
  end
end
