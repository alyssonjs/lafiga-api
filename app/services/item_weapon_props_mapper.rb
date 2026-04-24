# frozen_string_literal: true

# Converte `Item` (kind weapon) + coluna `props` JSONB no mesmo shape de hash
# que `EquipmentRules::WEAPON_TABLE` devolve (chaves symbol), para consumidores
# como `EquipmentRules.weapon_props`, `FightingStyleRules`, validação de off-hand.
#
# Fonte de verdade preferida: BD (`items`); o WEAPON_TABLE em código permanece
# apenas como fallback até remoção completa.
class ItemWeaponPropsMapper
  class << self
    # @return [Hash, nil] hash com chaves symbol alinhadas a WEAPON_TABLE, ou nil se não for arma / props vazios.
    def from_item(db_item)
      return nil unless db_item
      return nil unless db_item.respond_to?(:weapon?) && db_item.weapon?

      p = (db_item.props || {}).stringify_keys
      return nil if p.blank?

      props_tokens = Array(p['properties']).map { |x| x.to_s.downcase }
      hands = (p['hands'] || (props_tokens.include?('two-handed') ? 2 : 1)).to_i
      type = (p['type'].presence || 'melee').to_s
      category = (p['category'].presence || db_item.category).to_s

      ranged_no_thrown = type == 'ranged' && !truthy?(p['thrown']) && !props_tokens.include?('thrown') && !props_tokens.include?('arremesso')
      ammunition_flag = truthy?(p['ammunition']) || ranged_no_thrown || props_tokens.include?('ammunition')

      out = {
        type: type,
        hands: hands,
        light: truthy?(p['light']) || props_tokens.include?('light'),
        finesse: truthy?(p['finesse']) || props_tokens.include?('finesse'),
        versatile: truthy?(p['versatile']) || props_tokens.include?('versatile') || props_tokens.include?('versatil'),
        thrown: truthy?(p['thrown']) || props_tokens.include?('thrown') || props_tokens.include?('arremesso'),
        heavy: truthy?(p['heavy']) || props_tokens.include?('heavy') || props_tokens.include?('pesada'),
        reach: truthy?(p['reach']) || props_tokens.include?('reach') || props_tokens.include?('alcance'),
        loading: truthy?(p['loading']) || props_tokens.include?('loading') || props_tokens.include?('carregamento'),
        special: truthy?(p['special']) || props_tokens.include?('special') || props_tokens.include?('especial'),
        category: category,
        damage_die: p['damage_die'].presence,
        versatile_die: p['versatile_die'].presence,
        range: normalize_range(p['range'])
      }
      out[:ammunition] = true if ammunition_flag
      ammo_idx = p['ammunition_index'].presence || p['ammo_index'].presence
      out[:ammunition_index] = ammo_idx.to_s if ammunition_flag && ammo_idx.present?
      cc = cost_cp_from(p, db_item)
      out[:cost_cp] = cc if cc
      wk = weight_kg_from(p, db_item)
      out[:weight_kg] = wk if wk
      out
    end

    private

    def truthy?(v)
      v == true || v.to_s.downcase == 'true'
    end

    def normalize_range(raw)
      return nil if raw.blank?
      if raw.is_a?(Hash)
        n = raw['normal'] || raw[:normal]
        m = raw['max'] || raw[:max]
        return nil if n.blank?
        return m.present? ? "#{n}/#{m}" : n.to_s
      end
      raw.to_s
    end

    def cost_cp_from(p, db_item)
      return p['cost_cp'].to_i if p['cost_cp'].present?
      if db_item.respond_to?(:value_gp) && db_item.value_gp.present?
        return (db_item.value_gp.to_f * 100).to_i
      end
      nil
    end

    def weight_kg_from(p, db_item)
      return p['weight_kg'].to_f if p.key?('weight_kg') && !p['weight_kg'].nil?
      if db_item.respond_to?(:weight_kg) && !db_item.weight_kg.nil?
        return db_item.weight_kg.to_f
      end
      nil
    end
  end
end
