# Revisão monotônica do `turn_state`.
#
# O `turn_state` sempre foi gravado por SUBSTITUIÇÃO INTEGRAL a partir do que o
# cliente havia lido. Isso produziu duas famílias de bug recorrentes:
#
#   1. Escritas concorrentes se sobrescrevem — o 2º PATCH, montado sobre uma
#      leitura anterior, RESSUSCITA a chave que o 1º apagou (o TR imposto ficava
#      preso para sempre quando o portador gastava a Inspiração Bárdica).
#   2. Eco atrasado desfaz escrita nova — `combatant_upserted` de um snapshot
#      velho devolvia um dado já gasto / um +2 CA que já tinha expirado.
#
# `turn_state_rev` incrementa a cada escrita e viaja no serializer, então o
# cliente consegue (a) mandar ops granulares com `base_rev` e receber 409 quando
# alguém escreveu no meio, e (b) DESCARTAR eco com revisão menor que a conhecida.
class AddTurnStateRevToCombatCombatants < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_combatants, :turn_state_rev, :integer, default: 0, null: false
  end
end
