# frozen_string_literal: true

# Adiciona campo `progression_table` (rich-text/HTML) ao `klasses`.
#
# Contexto: o painel de detalhe da classe agora exibe um Collapse "Tabela
# de Progressao" acima de "Caracteristicas de Classe" — separado da aba
# "Historia" (que e o lore livre). DMs editam o conteudo no
# `ClassFormModal` via RichTextEditor (mesmo HTML usado na description),
# tipicamente colando uma tabela markdown/HTML do PHB com colunas:
# Nivel | Bonus de Proficiencia | Caracteristicas | <recursos da classe>.
#
# Tipo `text` (sem limite) — tabelas grandes (20 niveis x N colunas) podem
# passar 1KB em HTML.
class AddProgressionTableToKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :klasses, :progression_table, :text, null: true
  end
end
