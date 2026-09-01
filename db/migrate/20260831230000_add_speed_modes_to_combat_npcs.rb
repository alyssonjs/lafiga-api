# frozen_string_literal: true

# DESLOCAMENTO MULTI-MODO do NPC (31/08).
#
# `speed` era um inteiro só, e o importador achatava o statblock nele: o Swarm
# of Wasps (andar 5 / VOO 30) ficou andando 5 ft — o voo existia apenas como
# prosa nas notas, e nenhuma interface podia oferecê-lo porque não havia onde
# guardá-lo.
#
# `speed_modes` guarda o statblock inteiro: {"walk"=>5,"fly"=>30,"swim"=>2,
# "climb"=>2,"hover"=>true}. `speed` continua existindo como o modo de ANDAR
# (compat com tudo que já o lê); o orçamento de movimento passa a olhar os
# modos.
class AddSpeedModesToCombatNpcs < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_npcs, :speed_modes, :jsonb, null: false, default: {}
  end
end
