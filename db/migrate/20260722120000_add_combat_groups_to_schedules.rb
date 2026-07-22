# frozen_string_literal: true

# Grupos/times de combate por SESSÃO (aliado vs inimigo explícito). A party é o
# grupo padrão implícito; o mestre cria grupos só-da-sessão (cor no token) e move
# personagens entre eles SEM alterar a party do sistema (`Character.group_id`).
# jsonb opaco: { "groups" => [{id,name,color}], "members" => [{groupId,memberType,
# memberId,prevGroupId?}] }. Não copiado para a sessão seguinte (como dm_temp_npc).
class AddCombatGroupsToSchedules < ActiveRecord::Migration[6.0]
  def change
    add_column :schedules, :combat_groups, :jsonb, null: false, default: {}
  end
end
