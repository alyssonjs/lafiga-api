# frozen_string_literal: true

# Migration para suportar magias inatas de raças com usos por descanso
# Ex: Drow - Fogo das Fadas (1x por descanso longo)
class AddUsesToSheetKnownSpells < ActiveRecord::Migration[6.0]
  def change
    # Campo para indicar frequência de recarga (Long Rest, Short Rest, ou nil para cantrips)
    add_column :sheet_known_spells, :uses_per_rest, :string
    
    # Campo para rastrear usos restantes (usado apenas se uses_per_rest estiver definido)
    add_column :sheet_known_spells, :uses_remaining, :integer, default: 0
    
    # Adicionar índice para facilitar queries de magias com usos limitados
    add_index :sheet_known_spells, :uses_per_rest
    add_index :sheet_known_spells, :source
  end
end

