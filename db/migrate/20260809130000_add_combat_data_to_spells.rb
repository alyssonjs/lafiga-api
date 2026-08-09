# frozen_string_literal: true

# Adiciona `combat_data` (jsonb) em `spells`: campos MECÂNICOS derivados da
# Open5e (SRD 5e) para a plataforma de sessão/combate — dano, tipo, escala por
# espaço (upcast), teste de resistência, forma/tamanho de área, alcance e as
# condições que a magia INFLIGE ou REMOVE. Não guarda nome/descrição (esses já
# vivem em `name`/`desc`).
#
# Populado por `rake spells:import_combat_data` (seed em
# `db/seeds/spell_combat_data.json` + curadoria em
# `config/spell_combat_overrides.yml`). Default `{}` para as magias sem dado
# (homebrew/fora-do-SRD).
class AddCombatDataToSpells < ActiveRecord::Migration[6.0]
  def change
    add_column :spells, :combat_data, :jsonb, null: false, default: {}
  end
end
