class AddCompanionsToSheets < ActiveRecord::Migration[6.0]
  # Companion (familiar, montaria, companheiro animal, invocação) só vivia em
  # estado local do React: `addCompanion` fazia `setCharacters` e mais nada.
  # Medido antes da migration: 0 de todas as fichas tinham companion salvo —
  # qualquer um adicionado sumia no reload.
  #
  # Coluna própria e não `metadata`: metadata é a sacola do wizard e é gravada
  # por PATCH de blob inteiro (o controller tem comentário sobre isso já ter
  # apagado dados). Companion tem add/remove/update granulares.
  def change
    add_column :sheets, :companions, :jsonb, default: [], null: false
  end
end
