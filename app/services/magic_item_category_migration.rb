# frozen_string_literal: true

# Mapeia a categoria legada `wondrous item` (sub + contexto) para categoria API + flag.
module MagicItemCategoryMigration
  module_function

  # @return [String] categoria canónica (sem `wondrous item`)
  def from_legacy_wondrous_item(sub_category)
    sc = sub_category.to_s.strip.downcase
    cat = case sc
          when 'instrument' then 'tool'
          when 'consumable' then 'potion'
          when 'ring' then 'ring'
          else
            'gear'
          end
    [cat, true]
  end

  def legacy_wondrous_value?(raw)
    s = raw.to_s.strip.downcase
    s == 'wondrous item' || s == 'wondrous-item' || s == 'wondrousitem' || s == 'wondrous' ||
      s.start_with?('wondrous ')
  end
end
