# frozen_string_literal: true

# `training_overrides` passa a `training`.
#
# ⚠️ O nome estava a mentir por metade. A coluna nasceu (há uma hora, e ainda
# não deployada) só para a EXCEÇÃO de horas que o mestre crava por personagem.
# Agora guarda também quantas horas o personagem JÁ TREINOU — que é progresso,
# não sobrescrita. Renomear antes de existir em produção é barato; conviver com
# um nome que descreve metade do conteúdo é o que faz o próximo a mexer aqui
# procurar o dado no lugar errado.
class RenameTrainingOverridesToTraining < ActiveRecord::Migration[6.0]
  def change
    rename_column :sheets, :training_overrides, :training
  end
end
