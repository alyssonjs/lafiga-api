class AddUiPreferencesToUsers < ActiveRecord::Migration[6.0]
  # Preferências de UI persistidas por conta (segue o usuário entre dispositivos).
  # Hoje guarda só `combat_hotbar` (bool) — ativação, por DM, do novo hotbar de
  # combate (estilo BG3). Separado de `progression_settings` (que é config de XP
  # do DM) para não misturar semânticas.
  def change
    add_column :users, :ui_preferences, :jsonb, null: false, default: {}
  end
end
