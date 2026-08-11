# frozen_string_literal: true

# Biblioteca de ITENS/objetos do mapa. Além de textura/stamp/via, o DM importa
# "objetos" (kind='object') que são colocados no mapa como token-objeto.
# - `group_name`: agrupa VARIANTES (ex.: "Pedra Musgosa" com 4 variantes) DENTRO
#   de uma categoria. null = item avulso. Um grupo = linhas com mesma
#   (category, group_name).
# - `variant_order`: ordem estável da variante no grupo (drag-reorder).
class AddObjectKindAndGroupingToMapAssets < ActiveRecord::Migration[6.0]
  def up
    add_column :map_assets, :group_name, :string, limit: 60
    add_column :map_assets, :variant_order, :integer, null: false, default: 0
    add_index :map_assets, %i[kind category], name: 'index_map_assets_on_kind_and_category'
    add_index :map_assets, :group_name, name: 'index_map_assets_on_group_name'
  end

  def down
    remove_index :map_assets, name: 'index_map_assets_on_group_name'
    remove_index :map_assets, name: 'index_map_assets_on_kind_and_category'
    remove_column :map_assets, :variant_order
    remove_column :map_assets, :group_name
  end
end
