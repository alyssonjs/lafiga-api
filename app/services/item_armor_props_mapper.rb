# frozen_string_literal: true

# Converte `Item` (kind armor) + `props` JSONB no shape interno usado por
# `EquipmentRules::ARMOR_TABLE` ({ cat:, base:, dex_cap:, stealth_dis:, str_req: }).
class ItemArmorPropsMapper
  class << self
    # @return [Hash, nil] com chaves symbol alinhadas a ARMOR_TABLE
    def from_item(db_item)
      return nil unless db_item
      return nil unless db_item.respond_to?(:armor?) && db_item.armor?

      p = (db_item.props || {}).stringify_keys
      base = p['ac_base'] || p['base']
      return nil if base.blank?

      dex_cap =
        if p.key?('dex_cap') && !p['dex_cap'].nil?
          p['dex_cap'].to_i
        else
          nil
        end

      str_req =
        if p.key?('str_req') && !p['str_req'].nil?
          p['str_req'].to_i
        else
          nil
        end

      {
        cat: (p['armor_cat'].presence || db_item.category).to_s,
        base: base.to_i,
        dex_cap: dex_cap,
        stealth_dis: truthy?(p['stealth_dis']),
        str_req: str_req
      }
    end

    def shield_bonus_from_item(db_item)
      return nil unless db_item
      return nil unless db_item.respond_to?(:shield?) && db_item.shield?

      p = (db_item.props || {}).stringify_keys
      b = p['ac_bonus']
      b.present? ? b.to_i : 2
    end

    private

    def truthy?(v)
      v == true || v.to_s.downcase == 'true'
    end
  end
end
