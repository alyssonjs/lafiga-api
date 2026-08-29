# frozen_string_literal: true

# NPC de combate com DONO — a base compartilhada dos ALIADOS INVOCADOS.
#
# Hoje `CombatNpc` é sempre do Mestre: `player_owns_combatant?` só devolve true
# para combatente cujo `combatable` é um `Character` do usuário. Consequência
# medida: um familiar (Pacto da Corrente) ou um morto-vivo (patrono da Morte)
# entram no tracker como NPC e o JOGADOR não consegue mexer neles — nem na
# economia de ação deles, que é justamente o que a Investida do Familiar exige
# ("abre mão de um ataque para o familiar atacar com a REAÇÃO dele").
#
# ⚠️ APONTA PARA O PERSONAGEM, não para o usuário. O dono de um invocado é o
# PERSONAGEM que o invocou: o usuário é derivável (`character.user_id`), o
# contrário não. Isso também mantém a posse correta quando o Mestre cria o
# invocado em nome do jogador, e quando o mesmo usuário tem dois personagens na
# mesa.
#
# Aditiva e ANULÁVEL: todo NPC existente continua sendo do Mestre (nulo), e o
# código antigo que ignora a coluna segue funcionando durante o deploy.
class AddOwnerCharacterToCombatNpcs < ActiveRecord::Migration[6.0]
  def change
    add_reference :combat_npcs, :owner_character, null: true,
                  foreign_key: { to_table: :characters }, index: true
  end
end
