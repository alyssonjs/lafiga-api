# frozen_string_literal: true

# VARIANTE (agrupamento fino DENTRO de uma subcategoria). O DM seleciona itens na
# biblioteca e os unifica: passam a compartilhar `variant_group`. Na exibição, um
# grupo de variantes aparece COLAPSADO (1 representante + contagem) e expande inline.
# - `variant_group`: chave/nome do grupo de variantes. null = item não agrupado.
#   Um grupo = linhas com mesma (category, group_name, variant_group).
class AddVariantGroupToMapAssets < ActiveRecord::Migration[6.0]
  def up
    add_column :map_assets, :variant_group, :string, limit: 80
    add_index :map_assets, %i[category group_name variant_group],
              name: 'index_map_assets_on_cat_group_variant'
  end

  def down
    remove_index :map_assets, name: 'index_map_assets_on_cat_group_variant'
    remove_column :map_assets, :variant_group
  end
end
