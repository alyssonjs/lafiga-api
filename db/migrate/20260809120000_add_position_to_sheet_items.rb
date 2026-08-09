# frozen_string_literal: true

# Ordem manual do inventário (arrastar-e-soltar na bolsa). Até aqui os reads não
# faziam ORDER BY — a ordem exibida era acidental (default do Postgres). Passamos
# a ordenar por `position, id`; o backfill preserva a ordem atual (~inserção) ao
# semear `position = id` para todas as linhas existentes.
class AddPositionToSheetItems < ActiveRecord::Migration[6.0]
  def up
    add_column :sheet_items, :position, :integer

    # Backfill: semeia com o próprio id (monotônico por ficha) para manter a
    # ordem de inserção atual quando ordenarmos por `position, id`.
    execute <<~SQL.squish
      UPDATE sheet_items SET position = id WHERE position IS NULL
    SQL

    add_index :sheet_items, [:sheet_id, :position], name: 'index_sheet_items_on_sheet_id_and_position'
  end

  def down
    remove_index :sheet_items, name: 'index_sheet_items_on_sheet_id_and_position'
    remove_column :sheet_items, :position
  end
end
