# frozen_string_literal: true

# Categoria concreta (weapon, gear, ring, …) + `is_wondrous` no lugar de `wondrous item`.
class AddIsWondrousToMagicItemsAndItems < ActiveRecord::Migration[6.0]
  def up
    add_column :magic_items, :is_wondrous, :boolean, null: false, default: false
    add_column :items,     :is_wondrous, :boolean, null: false, default: false

    say_with_time 'Migra magic_items: categoria wondrous item' do
      MagicItem.reset_column_information
      MagicItem.where("lower(trim(category)) = 'wondrous item'").find_each do |mi|
        new_cat, wond = MagicItemCategoryMigration.from_legacy_wondrous_item(mi.sub_category)
        mi.update_columns(category: new_cat, is_wondrous: wond)
      end
    end

    say_with_time 'Migra items (kind magic_item): categoria wondrous item' do
      Item.reset_column_information
      Item.where(kind: 'magic_item').where("lower(trim(category)) = 'wondrous item'").find_each do |it|
        new_cat, wond = MagicItemCategoryMigration.from_legacy_wondrous_item(it.sub_category)
        it.update_columns(category: new_cat, is_wondrous: wond)
      end
    end
  end

  def down
    remove_column :magic_items, :is_wondrous
    remove_column :items,     :is_wondrous
  end
end
