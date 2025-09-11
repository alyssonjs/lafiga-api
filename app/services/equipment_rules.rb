class EquipmentRules
  ARMOR_TABLE = {
    # Light armor
    'padded'           => { cat: 'light',  base: 11, dex_cap: nil, stealth_dis: true,  str_req: nil },
    'leather'          => { cat: 'light',  base: 11, dex_cap: nil, stealth_dis: false, str_req: nil },
    'studded-leather'  => { cat: 'light',  base: 12, dex_cap: nil, stealth_dis: false, str_req: nil },
    # Medium armor
    'hide'             => { cat: 'medium', base: 12, dex_cap: 2,  stealth_dis: false, str_req: nil },
    'chain-shirt'      => { cat: 'medium', base: 13, dex_cap: 2,  stealth_dis: false, str_req: nil },
    'scale-mail'       => { cat: 'medium', base: 14, dex_cap: 2,  stealth_dis: true,  str_req: nil },
    'breastplate'      => { cat: 'medium', base: 14, dex_cap: 2,  stealth_dis: false, str_req: nil },
    'half-plate'       => { cat: 'medium', base: 15, dex_cap: 2,  stealth_dis: true,  str_req: nil },
    # Heavy armor
    'ring-mail'        => { cat: 'heavy',  base: 14, dex_cap: 0,  stealth_dis: true,  str_req: nil },
    'chain-mail'       => { cat: 'heavy',  base: 16, dex_cap: 0,  stealth_dis: true,  str_req: 13 },
    'splint'           => { cat: 'heavy',  base: 17, dex_cap: 0,  stealth_dis: true,  str_req: 15 },
    'plate'            => { cat: 'heavy',  base: 18, dex_cap: 0,  stealth_dis: true,  str_req: 15 },
  }.freeze

  SHIELD_INDEXES = ['shield', 'escudo'].freeze

  class << self
    def proficiencies_for(sheet)
      meta = sheet.metadata || {}
      cs = (meta['class_summary'] || {})
      rs = (meta['race_summary']  || {})
      armor = [*(cs['armor_proficiencies'] || []), *Array(rs.dig('proficiencies','armor') || [])].map(&:to_s)
      weapons = [*(cs['weapon_proficiencies'] || []), *Array(rs.dig('proficiencies','weapons') || [])].map(&:to_s)
      tools = [*(cs['tools'] || []), *Array(rs.dig('proficiencies','tools') || [])].map(&:to_s)
      { armor: armor, weapons: weapons, tools: tools }
    end

    def allowed_armor_categories(sheet)
      prof = proficiencies_for(sheet)
      set = Set.new
      prof[:armor].each do |a|
        t = a.downcase
        set << 'light'  if t.include?('leve') || t.include?('light')
        set << 'medium' if t.include?('média') || t.include?('media') || t.include?('medium')
        set << 'heavy'  if t.include?('pesad') || t.include?('heavy')
        set << 'shields' if t.include?('escudo') || t.include?('shield') || t.include?('escudos')
      end
      set
    end

    def dex_mod(sheet)
      CharacterRules.modifier(sheet.dex)
    end

    def ac_for(sheet:, armor_item: nil, shield_item: nil)
      dex = dex_mod(sheet)
      base_unarmored = 10 + dex

      if armor_item.nil?
        ac = base_unarmored
        return { ac: ac, source: 'Sem armadura', stealth_disadvantage: false, speed_penalty: false }
      end

      idx = normalize_index(armor_item)
      row = ARMOR_TABLE[idx]
      unless row
        # fallback: try from props_json
        if armor_item.props_json && armor_item.props_json['ac_base']
          base = armor_item.props_json['ac_base'].to_i
          cap = armor_item.props_json['dex_cap']
          add = cap.nil? ? dex : [dex, cap.to_i].min
          ac = base + [add, 0].max
          ac += 2 if shield_item
          return { ac: ac, source: armor_item.item_name, stealth_disadvantage: !!armor_item.props_json['stealth_disadvantage'], speed_penalty: false }
        end
        # unknown armor: treat as unarmored
        ac = base_unarmored
        ac += 2 if shield_item
        return { ac: ac, source: 'Desconhecida', stealth_disadvantage: false, speed_penalty: false }
      end

      add = if row[:dex_cap].nil?
              dex
            else
              [dex, row[:dex_cap]].min
            end
      add = 0 if add.nil?
      ac = row[:base] + [add, 0].max
      ac += 2 if shield_item
      speed_pen = row[:cat] == 'heavy' && row[:str_req] && (sheet.str.to_i < row[:str_req].to_i)

      { ac: ac, source: idx, stealth_disadvantage: !!row[:stealth_dis], speed_penalty: !!speed_pen }
    end

    def can_wear?(sheet:, armor_item:)
      prof = allowed_armor_categories(sheet)
      idx = normalize_index(armor_item)
      row = ARMOR_TABLE[idx]
      return { ok: true } unless row # unknown, allow
      cat = row[:cat]
      if !prof.include?(cat)
        return { ok: false, reason: "Sem proficiência em armadura #{cat}" }
      end
      { ok: true }
    end

    def is_shield?(item)
      key = (item.item_index || item.item_name || '').to_s.downcase
      SHIELD_INDEXES.any? { |t| key.include?(t) }
    end

    def normalize_index(item)
      key = (item.item_index || item.item_name || '').to_s.downcase
      key.strip.gsub(' ', '-').gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    end
  end
end

