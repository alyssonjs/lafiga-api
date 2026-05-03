# frozen_string_literal: true

# Adiciona campo `short_description` (tagline) ao `klasses`.
#
# Contexto: depois que `description` virou rich-text exibida na aba "Historia"
# do `CompendiumClasses` (refactor a5136ab4), o cabecalho do painel ficou sem
# texto curto. Este campo persiste o subtitulo opcional digitado no
# `ClassFormModal` (campo "Descricao Curta", input simples) e e exibido no
# cabecalho logo abaixo da linha de stats (`D12 · Força · TR: ...`).
#
# Tipo `string` (limite default ~255 chars) basta para uma tagline; nao
# precisa de rich-text.
class AddShortDescriptionToKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :klasses, :short_description, :string, null: true
  end
end
