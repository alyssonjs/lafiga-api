# frozen_string_literal: true

# Horas de treino cravadas pelo MESTRE, caso a caso.
#
# O catálogo (`proficiencies.metadata.training_hours`) diz o PADRÃO — quantas
# horas aquela proficiência custa em geral. Esta coluna é a exceção por
# personagem: "Ferramentas de ferreiro custam 120h, mas o filho do ferreiro
# aprende em 80".
#
# ⚠️ Coluna própria, e NÃO uma chave dentro de `dm_overrides`. Aquele serviço é
# uma lista BRANCA de números soltos (`str`..`cha`, `hp_max`, `speed_ft`), com
# `clamp` por nome de chave. Horas de treino são um MAPA sem chaves fixas,
# indexado por `proficiency.api_index`. Enfiá-las lá obrigaria a abrir a lista
# branca para qualquer chave — que é justamente o guarda que faz aquele serviço
# valer alguma coisa.
class AddTrainingOverridesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :training_overrides, :jsonb, null: false, default: {}
  end
end
