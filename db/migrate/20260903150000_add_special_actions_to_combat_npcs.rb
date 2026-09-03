# As ações especiais do companheiro morriam na invocação: o
# `SummonCompanionService` copiava nome/PV/CA/atributos/ataques e MAIS NADA. O
# Sopro Gelado do lobo invernal — CD, TR, 4d8 e o cone, tudo já estruturado
# desde o F2a — não chegava ao combate em forma nenhuma.
class AddSpecialActionsToCombatNpcs < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_npcs, :special_actions, :jsonb, default: []
  end
end
