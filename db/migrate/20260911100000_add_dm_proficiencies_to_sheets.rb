# frozen_string_literal: true

# Proficiências CONCEDIDAS pelo Mestre, avulsas.
#
# Antes disto não havia caminho nenhum: o formulário de proficiências edita o
# CATÁLOGO (o que existe no mundo e que raça/classe concede), e o passo de
# Perícias do wizard só oferece as da classe — e grava em
# `class_choices.per_level['1'].skills`, o que faria a perícia constar como
# vinda da CLASSE. Mentira na ficha, e o servidor só avisava.
#
# Coluna própria, irmã de `dm_overrides` e `training`, pela mesma razão das
# duas: a proveniência tem de sobreviver e ser visível. "O Mestre deu" não é a
# mesma coisa que "o personagem treinou".
class AddDmProficienciesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :dm_proficiencies, :jsonb, null: false, default: {}
  end
end
