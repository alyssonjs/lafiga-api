# frozen_string_literal: true

# FIXA ou de ESCOLHA — a distinção que faltava.
#
# ⚠️ Sem isto o índice mente por omissão: "Raça: Anão" em Ferramentas de
# ferreiro lê como se todo anão a tivesse, quando na verdade o anão escolhe UMA
# entre ferreiro, cervejeiro e pedreiro. Medido: das associações derivadas, 144
# vêm de um POOL de escolha e 94 são fixas — quase dois terços estavam a ser
# apresentadas erradas.
#
# `choose_count` guarda quantas se escolhem do pool (1 de 3, 2 de 18), porque
# "escolhe alguma" e "escolhe duas" dizem coisas diferentes a quem lê a ficha.
class AddGrantModeToProficiencySources < ActiveRecord::Migration[6.0]
  def change
    add_column :proficiency_sources, :grant_mode, :string, null: false, default: 'fixed'
    add_column :proficiency_sources, :choose_count, :integer
  end
end
