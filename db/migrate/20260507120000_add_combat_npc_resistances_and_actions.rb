# frozen_string_literal: true

# Fase 6E — Estende CombatNpc com campos para automação completa de monstros
# CR ≥ 10 (legendary actions, lair actions) e regras D&D 5e essenciais
# (resistências, imunidades, vulnerabilidades, condition immunities).
class AddCombatNpcResistancesAndActions < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_npcs, :resistances,         :jsonb, default: [], null: false
    add_column :combat_npcs, :damage_immunities,   :jsonb, default: [], null: false
    add_column :combat_npcs, :damage_vulnerabilities, :jsonb, default: [], null: false
    add_column :combat_npcs, :condition_immunities, :jsonb, default: [], null: false
    add_column :combat_npcs, :legendary_actions,   :jsonb, default: [], null: false
    add_column :combat_npcs, :lair_actions,        :jsonb, default: [], null: false
  end
end
