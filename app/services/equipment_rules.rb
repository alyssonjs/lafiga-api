class EquipmentRules
  WEAPON_TABLE = {
    # Simple melee
    'club'             => { type: 'melee', hands: 1, light: true,                          category: 'simple', damage_die: '1d4' },
    'clava'            => { type: 'melee', hands: 1, light: true,                          category: 'simple', damage_die: '1d4' },
    'dagger'           => { type: 'melee', hands: 1, light: true, finesse: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4' },
    'adaga'            => { type: 'melee', hands: 1, light: true, finesse: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4' },
    'greatclub'        => { type: 'melee', hands: 2,                                      category: 'simple', damage_die: '1d8' },
    'mace'             => { type: 'melee', hands: 1,                                      category: 'simple', damage_die: '1d6' },
    'maça'             => { type: 'melee', hands: 1,                                      category: 'simple', damage_die: '1d6' },
    'sickle'           => { type: 'melee', hands: 1, light: true,                         category: 'simple', damage_die: '1d4' },
    'foice'            => { type: 'melee', hands: 1, light: true,                         category: 'simple', damage_die: '1d4' },
    'spear'            => { type: 'melee', hands: 1, versatile: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6', versatile_die: '1d8' },
    'lança'            => { type: 'melee', hands: 1, versatile: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6', versatile_die: '1d8' },
    'quarterstaff'     => { type: 'melee', hands: 1, versatile: true,                     category: 'simple', damage_die: '1d6', versatile_die: '1d8' },
    'cajado'           => { type: 'melee', hands: 1, versatile: true,                     category: 'simple', damage_die: '1d6', versatile_die: '1d8' },
    'handaxe'          => { type: 'melee', hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6' },
    'machadinha'       => { type: 'melee', hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6' },
    'javelin'          => { type: 'melee', hands: 1, thrown: true, range: '30/120',       category: 'simple', damage_die: '1d6' },
    'azagaia'          => { type: 'melee', hands: 1, thrown: true, range: '30/120',       category: 'simple', damage_die: '1d6' },
    'light-hammer'     => { type: 'melee', hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4' },
    'martelo-leve'     => { type: 'melee', hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4' },

    # Simple ranged
    'light-crossbow'   => { type: 'ranged', hands: 2,                                     category: 'simple', damage_die: '1d8' },
    'besta-leve'       => { type: 'ranged', hands: 2,                                     category: 'simple', damage_die: '1d8' },
    'dart'             => { type: 'ranged', hands: 1, finesse: true,                      category: 'simple', damage_die: '1d4' },
    'dardo'            => { type: 'ranged', hands: 1, finesse: true,                      category: 'simple', damage_die: '1d4' },
    'shortbow'         => { type: 'ranged', hands: 2,                                     category: 'simple', damage_die: '1d6' },
    'arco-curto'       => { type: 'ranged', hands: 2,                                     category: 'simple', damage_die: '1d6' },
    'sling'            => { type: 'ranged', hands: 1,                                     category: 'simple', damage_die: '1d4' },
    'funda'            => { type: 'ranged', hands: 1,                                     category: 'simple', damage_die: '1d4' },

    # Martial melee
    'battleaxe'        => { type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8' },
    'machado-de-batalha'=>{ type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8' },
    'flail'            => { type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d8' },
    'glaive'           => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d10' },
    'halberd'          => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d10' },
    'alabarda'         => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d10' },
    'greataxe'         => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d12' },
    'machado-grande'   => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d12' },
    'greatsword'       => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '2d6' },
    'montante'         => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '2d6' },
    'maul'             => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '2d6' },
    'lance'            => { type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d12' },
    'lanca-de-cavalaria'=>{ type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d12' },
    'longsword'        => { type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8', versatile_die: '1d10' },
    'espada-longa'     => { type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8', versatile_die: '1d10' },
    'espada-bastarda'  => { type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8', versatile_die: '1d10' },
    'morningstar'      => { type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d8' },
    'maça-estrela'     => { type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d8' },
    'pike'             => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d10', reach: true, heavy: true },
    'pique'            => { type: 'melee', hands: 2,                                      category: 'martial', damage_die: '1d10' },
    'rapier'           => { type: 'melee', hands: 1, finesse: true,                       category: 'martial', damage_die: '1d8' },
    'scimitar'         => { type: 'melee', hands: 1, light: true, finesse: true,          category: 'martial', damage_die: '1d6' },
    'escimitarra'      => { type: 'melee', hands: 1, light: true, finesse: true,          category: 'martial', damage_die: '1d6' },
    'shortsword'       => { type: 'melee', hands: 1, light: true, finesse: true,          category: 'martial', damage_die: '1d6' },
    'espada-curta'     => { type: 'melee', hands: 1, light: true, finesse: true,          category: 'martial', damage_die: '1d6' },
    'trident'          => { type: 'melee', hands: 1, versatile: true, thrown: true, range: '20/60', category: 'martial', damage_die: '1d6', versatile_die: '1d8' },
    'tridente'         => { type: 'melee', hands: 1, versatile: true, thrown: true, range: '20/60', category: 'martial', damage_die: '1d6', versatile_die: '1d8' },
    'war-pick'         => { type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d8' },
    'picareta-de-guerra'=>{ type: 'melee', hands: 1,                                      category: 'martial', damage_die: '1d8' },
    'warhammer'        => { type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8', versatile_die: '1d10' },
    'martelo-de-guerra'=> { type: 'melee', hands: 1, versatile: true,                     category: 'martial', damage_die: '1d8', versatile_die: '1d10' },
    'whip'             => { type: 'melee', hands: 1, finesse: true, reach: true,          category: 'martial', damage_die: '1d4' },
    'chicote'          => { type: 'melee', hands: 1, finesse: true, reach: true,          category: 'martial', damage_die: '1d4' },

    # Martial ranged
    'blowgun'          => { type: 'ranged', hands: 1,                                     category: 'martial', damage_die: '1' },
    'zarabatana'       => { type: 'ranged', hands: 1,                                     category: 'martial', damage_die: '1' },
    'hand-crossbow'    => { type: 'ranged', hands: 1, loading: true, light: true,         category: 'martial', damage_die: '1d6', range: '30/120' },
    'besta-de-mao'     => { type: 'ranged', hands: 1, loading: true, light: true,         category: 'martial', damage_die: '1d6', range: '30/120' },
    'heavy-crossbow'   => { type: 'ranged', hands: 2, loading: true, heavy: true,         category: 'martial', damage_die: '1d10', range: '100/400' },
    'besta-pesada'     => { type: 'ranged', hands: 2, loading: true, heavy: true,         category: 'martial', damage_die: '1d10', range: '100/400' },
    'longbow'          => { type: 'ranged', hands: 2, heavy: true,                         category: 'martial', damage_die: '1d8', range: '150/600' },
    'arco-longo'       => { type: 'ranged', hands: 2, heavy: true,                         category: 'martial', damage_die: '1d8', range: '150/600' },
    'net'              => { type: 'ranged', hands: 1, special: true,                       category: 'martial', damage_die: '' },
    'rede'             => { type: 'ranged', hands: 1, special: true,                       category: 'martial', damage_die: '' }
  }.freeze
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

    def effective_scores(sheet)
      base = {
        str: sheet.str.to_i, dex: sheet.dex.to_i, con: sheet.con.to_i,
        int: sheet.int.to_i, wis: sheet.wis.to_i, cha: sheet.cha.to_i
      }
      meta = sheet.metadata || {}
      inc = { str: 0, dex: 0, con: 0, int: 0, wis: 0, cha: 0 }

      # Race bonuses
      begin
        rb = meta['race_bonuses_applied'] || {}
        inc[:str] += rb['str'].to_i
        inc[:dex] += rb['dex'].to_i
        inc[:con] += rb['con'].to_i
        inc[:int] += rb['int'].to_i
        inc[:wis] += rb['wis'].to_i
        inc[:cha] += rb['cha'].to_i
      rescue; end

      # ASIs from per-level choices
      begin
        per = (meta.dig('class_choices','per_level') || {}).values
        per.each do |row|
          asi = row.is_a?(Hash) ? row['asi'] : nil
          next unless asi.is_a?(Hash)
          if asi['mode'] == 'attributes'
            attrs = Array(asi['attributes'])
            map = { 'STR'=>'str','DEX'=>'dex','DES'=>'dex','CON'=>'con','INT'=>'int','WIS'=>'wis','SAB'=>'wis','CHA'=>'cha','CAR'=>'cha' }
            if attrs.length == 1
              k = map[attrs.first.to_s.upcase]
              inc[k.to_sym] += 2 if k
            else
              attrs.first(2).each do |a|
                k = map[a.to_s.upcase]
                inc[k.to_sym] += 1 if k
              end
            end
          elsif asi['mode'] == 'feat'
            # Some feats grant ability bonuses via choices
            choices = asi['choices'] || {}
            begin
              ab = choices['ability_bonuses'] || {}
              ab.each { |k,v| key = k.to_s.downcase; map = { 'str'=>:str,'dex'=>:dex,'con'=>:con,'int'=>:int,'wis'=>:wis,'cha'=>:cha,'for'=>:str,'des'=>:dex,'sab'=>:wis,'car'=>:cha }; sym = map[key]; inc[sym] += v.to_i if sym }
            rescue; end
          end
        end
      rescue; end

      # Ability bonuses from feats in metadata
      begin
        feats_meta = Array(meta['feats'])
        feats_meta.each do |f|
          ab = f['ability_bonuses'] || {}
          ab.each do |k, v|
            key = k.to_s.downcase
            map = { 'str'=>:str, 'dex'=>:dex, 'con'=>:con, 'int'=>:int, 'wis'=>:wis, 'cha'=>:cha, 'for'=>:str, 'des'=>:dex, 'sab'=>:wis, 'car'=>:cha }
            sym = map[key]
            inc[sym] += v.to_i if sym
          end
        end
      rescue; end

      out = {}
      base.each_key do |k|
        out[k] = base[k] + inc[k]
      end
      out
    end

    def dex_mod(sheet)
      CharacterRules.modifier(effective_scores(sheet)[:dex])
    end

    def con_mod(sheet)
      CharacterRules.modifier(effective_scores(sheet)[:con])
    end

    def wis_mod(sheet)
      CharacterRules.modifier(effective_scores(sheet)[:wis])
    end

    def class_names(sheet)
      begin
        sheet.sheet_klasses.includes(:klass).map { |sk| (sk.klass&.name || '').downcase }
      rescue
        []
      end
    end

    def ac_for(sheet:, armor_item: nil, shield_item: nil)
      dex = dex_mod(sheet)
      base_unarmored = 10 + dex

      if armor_item.nil?
        # Unarmored cases: consider Barbarian/Monk Unarmored Defense and shield rules
        names = class_names(sheet)
        has_barb = names.any? { |n| n.include?('bárbar') || n.include?('barbar') }
        has_monk = names.any? { |n| n.include?('monge') || n.include?('monk') }

        base_ac = base_unarmored + (shield_item ? 2 : 0)
        best = { ac: base_ac, source: shield_item ? 'Sem armadura + Escudo' : 'Sem armadura' }

        if has_barb
          barb_ac = 10 + dex + con_mod(sheet) + (shield_item ? 2 : 0)
          if barb_ac > best[:ac]
            best = { ac: barb_ac, source: shield_item ? 'Sem armadura (Bárbaro) + Escudo' : 'Sem armadura (Bárbaro)' }
          end
        end

        if has_monk && !shield_item
          monk_ac = 10 + dex + wis_mod(sheet)
          if monk_ac > best[:ac]
            best = { ac: monk_ac, source: 'Sem armadura (Monge)' }
          end
        end

        return best.merge(stealth_disadvantage: false, speed_penalty: false)
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

      src = idx
      src += ' + Escudo' if shield_item
      { ac: ac, source: src, stealth_disadvantage: !!row[:stealth_dis], speed_penalty: !!speed_pen }
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

    def is_weapon?(item)
      return false unless item
      key = normalize_index(item)
      return true if WEAPON_TABLE.key?(key)
      # fallback by category
      (item.category || '').to_s.downcase.include?('weapon')
    end

    def normalize_index(item)
      key = (item.item_index || item.item_name || '').to_s.downcase
      key.strip.gsub(' ', '-').gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    end

    def weapon_props(item)
      return nil unless item
      key = normalize_index(item)
      row = WEAPON_TABLE[key]
      unless row
        # best-effort from props_json
        props = (item.respond_to?(:props_json) ? item.props_json : (item[:props_json] rescue {})) || {}
        return {
          type: props['type'] || (props['ranged'] ? 'ranged' : 'melee'),
          hands: (props['hands'] || (props['two_handed'] ? 2 : 1)).to_i,
          light: !!props['light'],
          finesse: !!props['finesse'],
          versatile: !!props['versatile'],
          category: props['category'],
          damage_die: props['damage_die'],
          versatile_die: props['versatile_die'],
          heavy: !!props['heavy'],
          reach: !!props['reach'],
          loading: !!props['loading'],
          special: !!props['special'],
          thrown: !!props['thrown'],
          range: props['range']
        }
      end
      row
    end
  end
end
