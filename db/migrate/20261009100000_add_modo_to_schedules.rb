# frozen_string_literal: true

# O MODO da mesa (09/10; L0.8, plano B3): `campanha` (a sessão de sempre, com o Mestre), `vila` (a mesa do jogo
# persistente), `missao` (um contrato) e `encontro` (o combate automático). Todas reaproveitam o combate, os NPCs, o
# log, o feed e as camadas da sessão.
#
# Só a CAMPANHA ocupa o "slot único" do grupo e do criador: os dois índices de sessão aberta passam a filtrar
# `modo = 'campanha'`, para a mesa da vila conviver com a sessão de campanha. Os pushes de sessão também só olham a
# campanha (no código).
class AddModoToSchedules < ActiveRecord::Migration[6.0]
  ABERTA = 'status = ANY (ARRAY[0, 1, 2]) AND sandbox = false'

  def up
    add_column :schedules, :modo, :string, null: false, default: 'campanha'
    recria_indices("#{ABERTA} AND modo = 'campanha'")
  end

  def down
    recria_indices(ABERTA)
    remove_column :schedules, :modo
  end

  private

  def recria_indices(aberta)
    remove_index :schedules, name: 'idx_schedules_open_per_group'
    remove_index :schedules, name: 'idx_schedules_open_per_creator_date'
    add_index :schedules, :group_id, unique: true, name: 'idx_schedules_open_per_group',
                                     where: "group_id IS NOT NULL AND #{aberta}"
    add_index :schedules, %i[created_by_user_id date_dimension_id], unique: true,
                                                                    name: 'idx_schedules_open_per_creator_date',
                                                                    where: "created_by_user_id IS NOT NULL AND #{aberta}"
  end
end
