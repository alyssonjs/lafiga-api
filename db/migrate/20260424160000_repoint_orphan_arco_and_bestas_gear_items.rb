# frozen_string_literal: true

# Remove itens de catálogo criados por engano como `kind: :gear` (ItemResolver
# sem categoria "Armas") para nomes ambíguos "Arco" / "bestas leve".
# Realinha sheet_items para o api_index de arma canónico e apaga o Item órfão.
class RepointOrphanArcoAndBestasGearItems < ActiveRecord::Migration[6.0]
  ORPHANS = {
    'arco' => 'arco-curto',
    'bestas-leve' => 'besta-leve',
  }.freeze

  def up
    ORPHANS.each do |bad_slug, good_slug|
      bad = Item.find_by(api_index: bad_slug)
      good = Item.find_by(api_index: good_slug)
      next unless bad && good

      SheetItem.where(item_id: bad.id).find_each do |si|
        si.update_columns(item_id: good.id, item_index: good_slug)
      end
      bad.delete
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
