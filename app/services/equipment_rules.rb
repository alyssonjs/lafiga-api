class EquipmentRules
  # Conversão de moedas -> sempre guardar em cp (cobre) para contas
  CURRENCY = {
    'pc' => 1,     # cobre
    'pp' => 10,    # prata
    'po' => 100,   # ouro
    'pl' => 1000,  # platina (se aparecer)
  }.freeze

  # ===== ARSENAL =====
  # @deprecated_request_time_source Em runtime, preferir `Item` + `props`
  # (ver `ItemWeaponPropsMapper` / `EquipmentRules.weapon_props`). Esta tabela
  # permanece só como fallback até cobertura DB = 100% e remoção planejada.
  # Adicionados: cost_cp (inteiro, em cp) e weight_kg (Float, em kg)
  WEAPON_TABLE = {
    # Simples Corpo-a-Corpo
    'club'              => { type: 'melee',  hands: 1, light: true,                           category: 'simple',  damage_die: '1d4', cost_cp: 10,  weight_kg: 1.0  }, # Porrete 1 pp, ~1 kg
    'clava'             => { type: 'melee',  hands: 1, light: true,                           category: 'simple',  damage_die: '1d4', cost_cp: 10,  weight_kg: 1.0  },
    'dagger'            => { type: 'melee',  hands: 1, light: true, finesse: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4', cost_cp: 200, weight_kg: 0.5 },
    'adaga'             => { type: 'melee',  hands: 1, light: true, finesse: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4', cost_cp: 200, weight_kg: 0.5 },
    'greatclub'         => { type: 'melee',  hands: 2,                                         category: 'simple',  damage_die: '1d8', cost_cp: 20,  weight_kg: 5.0  }, # Clava grande 2 pp, 5 kg
    'mace'              => { type: 'melee',  hands: 1,                                         category: 'simple',  damage_die: '1d6', cost_cp: 500, weight_kg: 2.0  }, # Maça 5 po? (texto mostra 2 po/5 po em blocos distintos; manter 5 po = 500 cp é o padrão)
    'maça'              => { type: 'melee',  hands: 1,                                         category: 'simple',  damage_die: '1d6', cost_cp: 500, weight_kg: 2.0  },
    'sickle'            => { type: 'melee',  hands: 1, light: true,                            category: 'simple',  damage_die: '1d4', cost_cp: 100, weight_kg: 1.0  }, # Foice curta 1 po, 1 kg
    'foice'             => { type: 'melee',  hands: 1, light: true,                            category: 'simple',  damage_die: '1d4', cost_cp: 100, weight_kg: 1.0  },
    'spear'             => { type: 'melee',  hands: 1, versatile: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6', versatile_die: '1d8', cost_cp: 100, weight_kg: 1.5 },
    'lança'             => { type: 'melee',  hands: 1, versatile: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6', versatile_die: '1d8', cost_cp: 100, weight_kg: 1.5 },
    'quarterstaff'      => { type: 'melee',  hands: 1, versatile: true,                        category: 'simple',  damage_die: '1d6', versatile_die: '1d8', cost_cp: 20,  weight_kg: 2.0  }, # Bordão 2 pp, 2 kg
    'cajado'            => { type: 'melee',  hands: 1, versatile: true,                        category: 'simple',  damage_die: '1d6', versatile_die: '1d8', cost_cp: 20,  weight_kg: 2.0  },
    'handaxe'           => { type: 'melee',  hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6', cost_cp: 500, weight_kg: 1.0 }, # Machadinha 5 po, 1 kg
    'machadinha'        => { type: 'melee',  hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d6', cost_cp: 500, weight_kg: 1.0 },
    'javelin'           => { type: 'melee',  hands: 1, thrown: true, range: '30/120',          category: 'simple',  damage_die: '1d6', cost_cp: 50,  weight_kg: 1.0  }, # Azagaia 5 pp, 1 kg
    'azagaia'           => { type: 'melee',  hands: 1, thrown: true, range: '30/120',          category: 'simple',  damage_die: '1d6', cost_cp: 50,  weight_kg: 1.0  },
    'light-hammer'      => { type: 'melee',  hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4', cost_cp: 200, weight_kg: 1.0 }, # Martelo leve 2 po? (tabela “1 po 5 po 2 po” – adotar 2 po padrão SRD)
    'martelo-leve'      => { type: 'melee',  hands: 1, light: true, thrown: true, range: '20/60', category: 'simple', damage_die: '1d4', cost_cp: 200, weight_kg: 1.0 },

    # Simples à Distância
    'light-crossbow'    => { type: 'ranged', hands: 2,                                          category: 'simple',  damage_die: '1d8', range: '80/320', loading: true, cost_cp: 2500, weight_kg: 2.5 }, # Besta leve 25 po, 2,5 kg
    'besta-leve'        => { type: 'ranged', hands: 2,                                          category: 'simple',  damage_die: '1d8', range: '80/320', loading: true, cost_cp: 2500, weight_kg: 2.5 },
    'dart'              => { type: 'ranged', hands: 1, finesse: true,                           category: 'simple',  damage_die: '1d4', range: '20/60', cost_cp: 5,    weight_kg: 0.1 }, # Dardo 5 pc, 0,1 kg
    'dardo'             => { type: 'ranged', hands: 1, finesse: true,                           category: 'simple',  damage_die: '1d4', range: '20/60', cost_cp: 5,    weight_kg: 0.1 },
    'shortbow'          => { type: 'ranged', hands: 2,                                          category: 'simple',  damage_die: '1d6', range: '80/320', cost_cp: 2500, weight_kg: 1.0 }, # Arco curto 25 po, 1 kg
    'arco-curto'        => { type: 'ranged', hands: 2,                                          category: 'simple',  damage_die: '1d6', range: '80/320', cost_cp: 2500, weight_kg: 1.0 },
    'sling'             => { type: 'ranged', hands: 1,                                          category: 'simple',  damage_die: '1d4', range: '30/120', cost_cp: 10,   weight_kg: 0.0 }, # Funda 1 pp, peso n/a
    'funda'             => { type: 'ranged', hands: 1,                                          category: 'simple',  damage_die: '1d4', range: '30/120', cost_cp: 10,   weight_kg: 0.0 },

    # Marciais Corpo-a-Corpo
    'battleaxe'         => { type: 'melee',  hands: 1, versatile: true,                         category: 'martial', damage_die: '1d8', versatile_die: '1d10', cost_cp: 1000, weight_kg: 2.0 }, # 10 po, 2 kg
    'machado-de-batalha'=> { type: 'melee',  hands: 1, versatile: true,                         category: 'martial', damage_die: '1d8', versatile_die: '1d10', cost_cp: 1000, weight_kg: 2.0 },
    'flail'             => { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d8', cost_cp: 1000, weight_kg: 1.0 }, # 10 po, 1 kg
    'glaive'            => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '1d10', reach: true, heavy: true, cost_cp: 2000, weight_kg: 3.0 },
    'halberd'           => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '1d10', reach: true, heavy: true, cost_cp: 2000, weight_kg: 3.0 },
    'alabarda'          => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '1d10', reach: true, heavy: true, cost_cp: 2000, weight_kg: 3.0 },
    'greataxe'          => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '1d12', heavy: true, cost_cp: 3000, weight_kg: 3.5 },
    'machado-grande'    => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '1d12', heavy: true, cost_cp: 3000, weight_kg: 3.5 },
    'greatsword'        => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '2d6',  heavy: true, cost_cp: 5000, weight_kg: 3.0 },
    'montante'          => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '2d6',  heavy: true, cost_cp: 5000, weight_kg: 3.0 },
    'maul'              => { type: 'melee',  hands: 2,                                          category: 'martial', damage_die: '2d6',  heavy: true, cost_cp: 1000, weight_kg: 5.0 },
    'lance'             => { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d12', reach: true, special: true, cost_cp: 1000, weight_kg: 2.5 }, # Lança de montaria
    'lanca-de-cavalaria'=> { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d12', reach: true, special: true, cost_cp: 1000, weight_kg: 2.5 },
    'longsword'         => { type: 'melee',  hands: 1, versatile: true,                         category: 'martial', damage_die: '1d8', versatile_die: '1d10', cost_cp: 1500, weight_kg: 1.5 },
    'espada-longa'      => { type: 'melee',  hands: 1, versatile: true,                         category: 'martial', damage_die: '1d8', versatile_die: '1d10', cost_cp: 1500, weight_kg: 1.5 },
    'morningstar'       => { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d8',  cost_cp: 1500, weight_kg: 2.0 }, # Maça estrela
    'maça-estrela'      => { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d8',  cost_cp: 1500, weight_kg: 2.0 },
    'pike'              => { type: 'melee',  hands: 2, reach: true, heavy: true,                category: 'martial', damage_die: '1d10', cost_cp: 500,  weight_kg: 3.0 }, # Pique 5 po? (texto mistura; manter 5 po padrão SRD=500 cp)
    'pique'             => { type: 'melee',  hands: 2, reach: true, heavy: true,                category: 'martial', damage_die: '1d10', cost_cp: 500,  weight_kg: 3.0 },
    'rapier'            => { type: 'melee',  hands: 1, finesse: true,                           category: 'martial', damage_die: '1d8',  cost_cp: 2500, weight_kg: 1.0 },
    'scimitar'          => { type: 'melee',  hands: 1, light: true, finesse: true,              category: 'martial', damage_die: '1d6',  cost_cp: 2500, weight_kg: 1.5 },
    'escimitarra'       => { type: 'melee',  hands: 1, light: true, finesse: true,              category: 'martial', damage_die: '1d6',  cost_cp: 2500, weight_kg: 1.5 },
    'shortsword'        => { type: 'melee',  hands: 1, light: true, finesse: true,              category: 'martial', damage_die: '1d6',  cost_cp: 1000, weight_kg: 1.0 },
    'espada-curta'      => { type: 'melee',  hands: 1, light: true, finesse: true,              category: 'martial', damage_die: '1d6',  cost_cp: 1000, weight_kg: 1.0 },
    'trident'           => { type: 'melee',  hands: 1, versatile: true, thrown: true, range: '20/60', category: 'martial', damage_die: '1d6', versatile_die: '1d8', cost_cp: 500, weight_kg: 2.0 },
    'tridente'          => { type: 'melee',  hands: 1, versatile: true, thrown: true, range: '20/60', category: 'martial', damage_die: '1d6', versatile_die: '1d8', cost_cp: 500, weight_kg: 2.0 },
    'war-pick'          => { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d8',  cost_cp: 500,  weight_kg: 1.0 },
    'picareta-de-guerra'=> { type: 'melee',  hands: 1,                                          category: 'martial', damage_die: '1d8',  cost_cp: 500,  weight_kg: 1.0 },
    'warhammer'         => { type: 'melee',  hands: 1, versatile: true,                         category: 'martial', damage_die: '1d8',  versatile_die: '1d10', cost_cp: 1500, weight_kg: 1.0 },
    'martelo-de-guerra' => { type: 'melee',  hands: 1, versatile: true,                         category: 'martial', damage_die: '1d8',  versatile_die: '1d10', cost_cp: 1500, weight_kg: 1.0 },
    'whip'              => { type: 'melee',  hands: 1, finesse: true, reach: true,              category: 'martial', damage_die: '1d4',  cost_cp: 200,  weight_kg: 1.0 },
    'chicote'           => { type: 'melee',  hands: 1, finesse: true, reach: true,              category: 'martial', damage_die: '1d4',  cost_cp: 200,  weight_kg: 1.0 },

    # Marciais à Distância
    'blowgun'           => { type: 'ranged', hands: 1,                                          category: 'martial', damage_die: '1',    range: '25/100', loading: true, cost_cp: 1000, weight_kg: 0.5 }, # Zarabatana 10 po, 0,5 kg
    'zarabatana'        => { type: 'ranged', hands: 1,                                          category: 'martial', damage_die: '1',    range: '25/100', loading: true, cost_cp: 1000, weight_kg: 0.5 },
    'hand-crossbow'     => { type: 'ranged', hands: 1, loading: true, light: true,              category: 'martial', damage_die: '1d6',  range: '30/120', cost_cp: 7500, weight_kg: 1.5 }, # Besta de mão 75 po, 1,5 kg
    'besta-de-mao'      => { type: 'ranged', hands: 1, loading: true, light: true,              category: 'martial', damage_die: '1d6',  range: '30/120', cost_cp: 7500, weight_kg: 1.5 },
    'heavy-crossbow'    => { type: 'ranged', hands: 2, loading: true, heavy: true,              category: 'martial', damage_die: '1d10', range: '100/400', cost_cp: 5000, weight_kg: 4.5 }, # Besta pesada 50 po, 4,5 kg
    'besta-pesada'      => { type: 'ranged', hands: 2, loading: true, heavy: true,              category: 'martial', damage_die: '1d10', range: '100/400', cost_cp: 5000, weight_kg: 4.5 },
    'longbow'           => { type: 'ranged', hands: 2, heavy: true,                             category: 'martial', damage_die: '1d8',  range: '150/600', cost_cp: 5000, weight_kg: 1.5 }, # Arco longo 50 po, 1,5 kg
    'arco-longo'        => { type: 'ranged', hands: 2, heavy: true,                             category: 'martial', damage_die: '1d8',  range: '150/600', cost_cp: 5000, weight_kg: 1.5 },
    'net'               => { type: 'ranged', hands: 1, special: true,                            category: 'martial', damage_die: '',     range: '5/15',   cost_cp: 100,  weight_kg: 1.5 }, # Rede 1 po, 1,5 kg
    'rede'              => { type: 'ranged', hands: 1, special: true,                            category: 'martial', damage_die: '',     range: '5/15',   cost_cp: 100,  weight_kg: 1.5 }
  }.freeze

  # @deprecated_request_time_source Preferir `Item` + `ItemArmorPropsMapper` em
  # `EquipmentRules.ac_for`; manter esta tabela só como fallback até remoção.
  ARMOR_TABLE = {
    # (mantida como estava; se quiser adiciono custo/peso da armadura também)
    'padded'           => { cat: 'light',  base: 11, dex_cap: nil, stealth_dis: true,  str_req: nil },
    'leather'          => { cat: 'light',  base: 11, dex_cap: nil, stealth_dis: false, str_req: nil },
    'studded-leather'  => { cat: 'light',  base: 12, dex_cap: nil, stealth_dis: false, str_req: nil },
    'hide'             => { cat: 'medium', base: 12, dex_cap: 2,  stealth_dis: false, str_req: nil },
    'chain-shirt'      => { cat: 'medium', base: 13, dex_cap: 2,  stealth_dis: false, str_req: nil },
    'scale-mail'       => { cat: 'medium', base: 14, dex_cap: 2,  stealth_dis: true,  str_req: nil },
    'breastplate'      => { cat: 'medium', base: 14, dex_cap: 2,  stealth_dis: false, str_req: nil },
    'half-plate'       => { cat: 'medium', base: 15, dex_cap: 2,  stealth_dis: true,  str_req: nil },
    'ring-mail'        => { cat: 'heavy',  base: 14, dex_cap: 0,  stealth_dis: true,  str_req: nil },
    'chain-mail'       => { cat: 'heavy',  base: 16, dex_cap: 0,  stealth_dis: true,  str_req: 13 },
    'splint'           => { cat: 'heavy',  base: 17, dex_cap: 0,  stealth_dis: true,  str_req: 15 },
    'plate'            => { cat: 'heavy',  base: 18, dex_cap: 0,  stealth_dis: true,  str_req: 15 },
  }.freeze

  # Itens genéricos (extensível)
  # Ex.: 'corda-de-seda-15-m' => { cost_cp: 1000, weight_kg: 2.5 }
  ITEM_TABLE = {
    # (adicione aqui com o mesmo esquema quando quiser cobrir o bloco inteiro de “Equipamento”)
  }.freeze

  SHIELD_INDEXES = ['shield', 'escudo'].freeze

  class << self
    # ======= NOVO: utilidades de preço/peso =======
    def cp(amount, unit)
      (amount.to_f * CURRENCY[unit.to_s.downcase]).to_i
    end

    def format_currency(cp_amount)
      # Converte cp -> po/pp/pc amigável (prioriza po/pp)
      po, rem = cp_amount.divmod(100)
      pp, pc = rem.divmod(10)
      parts = []
      parts << "#{po} po" if po > 0
      parts << "#{pp} pp" if pp > 0
      parts << "#{pc} pc" if pc > 0 || parts.empty?
      parts.join(' ')
    end

    def item_weight_kg(item)
      # Preferir coluna do banco quando existir
      if item.respond_to?(:weight_kg) && !item.weight_kg.nil?
        return item.weight_kg.to_f
      end
      key = normalize_index(item)
      db_item = item.respond_to?(:item) && item.item ? item.item : nil
      if !db_item && defined?(Item)
        cand = Item.find_by(api_index: key)
        db_item = cand if cand
      end
      if db_item&.respond_to?(:weight_kg) && !db_item.weight_kg.nil?
        return db_item.weight_kg.to_f
      end
      if db_item&.weapon?
        mapped = ItemWeaponPropsMapper.from_item(db_item)
        return mapped[:weight_kg].to_f if mapped&.dig(:weight_kg)
      end
      if WEAPON_TABLE[key] && WEAPON_TABLE[key][:weight_kg]
        return WEAPON_TABLE[key][:weight_kg].to_f
      end
      if ITEM_TABLE[key] && ITEM_TABLE[key][:weight_kg]
        return ITEM_TABLE[key][:weight_kg].to_f
      end
      # fallback via props_json
      props = safe_props(item)
      (props['weight_kg'] || props['weight'] || 0).to_f
    end

    def item_cost_cp(item)
      # Preferir coluna normalizada do banco quando existir
      if item.respond_to?(:value_gp) && !item.value_gp.nil?
        return (item.value_gp.to_f * 100).to_i
      end
      key = normalize_index(item)
      db_item = item.respond_to?(:item) && item.item ? item.item : nil
      if !db_item && defined?(Item)
        cand = Item.find_by(api_index: key)
        db_item = cand if cand
      end
      if db_item&.respond_to?(:value_gp) && !db_item.value_gp.nil?
        return (db_item.value_gp.to_f * 100).to_i
      end
      if db_item&.weapon?
        mapped = ItemWeaponPropsMapper.from_item(db_item)
        return mapped[:cost_cp].to_i if mapped&.dig(:cost_cp)
      end
      if WEAPON_TABLE[key] && WEAPON_TABLE[key][:cost_cp]
        return WEAPON_TABLE[key][:cost_cp].to_i
      end
      if ITEM_TABLE[key] && ITEM_TABLE[key][:cost_cp]
        return ITEM_TABLE[key][:cost_cp].to_i
      end
      # fallback via props_json (aceita { cost_cp: 123 } OU { cost: {amount: 5, unit: 'po'} })
      props = safe_props(item)
      if props['cost_cp']
        return props['cost_cp'].to_i
      elsif props['cost'].is_a?(Hash)
        return cp(props['cost']['amount'], props['cost']['unit'] || 'pc')
      end
      0
    end

    # Soma custo/peso de uma coleção (Array de objetos de inventário)
    def inventory_totals(items)
      total_cp = 0
      total_kg = 0.0
      Array(items).each do |it|
        qty = (it.respond_to?(:quantity) ? it.quantity : it[:quantity] rescue 1).to_i
        qty = 1 if qty <= 0
        total_cp += item_cost_cp(it) * qty
        total_kg += item_weight_kg(it) * qty
      end
      { cost_cp: total_cp, weight_kg: total_kg, cost_human: format_currency(total_cp) }
    end

    def safe_props(item)
      # Suporta AR Item com coluna props (JSONB) e sheet_items.props_json
      if item.respond_to?(:props)
        item.props || {}
      elsif item.respond_to?(:props_json)
        item.props_json || {}
      elsif item.is_a?(Hash)
        item[:props] || item[:props_json] || {}
      else
        {}
      end
    end

    # ======= (resto da classe mantém igual) =======

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
      ProficiencyResolver.resolve_armor_categories(prof[:armor])
    end

    def allowed_weapon_profile(sheet)
      prof = proficiencies_for(sheet)
      ProficiencyResolver.resolve_weapons(prof[:weapons])
    end

    def is_shield?(item)
      return false unless item
      key = normalize_index(item)
      SHIELD_INDEXES.include?(key)
    end

    def ac_for(sheet:, armor_item:, shield_item:)
      dex_mod = CharacterRules.modifier(sheet.dex)

      armor_category = 'none'
      stealth_disadvantage = false
      speed_penalty = false
      armor_data = nil

      if armor_item
        key = normalize_index(armor_item)
        armor_data = ARMOR_TABLE[key]
        unless armor_data
          db_armor = armor_item.respond_to?(:item) && armor_item.item&.armor? ? armor_item.item : nil
          if !db_armor && defined?(Item)
            cand = Item.find_by(api_index: key)
            db_armor = cand if cand&.armor?
          end
          armor_data = ItemArmorPropsMapper.from_item(db_armor) if db_armor
        end
        if armor_data
          base = armor_data[:base]
          cap = armor_data[:dex_cap]
          dex_bonus = cap.nil? ? dex_mod : [dex_mod, cap].min
          ac = base + dex_bonus
          source = armor_item.respond_to?(:item_name) ? armor_item.item_name : key
          armor_category = armor_data[:cat].to_s
          stealth_disadvantage = !!armor_data[:stealth_dis]
          # 5e: armaduras com requisito de FOR não atendido aplicam -10 ft de
          # deslocamento (a regra "speed_penalty" do summary).
          if armor_data[:str_req] && sheet.str.to_i < armor_data[:str_req].to_i
            speed_penalty = true
          end
        else
          ac = 10 + dex_mod
          source = 'Sem armadura'
        end
      else
        ac = 10 + dex_mod
        source = 'Sem armadura'
      end

      if shield_item
        shield_bonus = 2
        if shield_item.respond_to?(:item) && shield_item.item&.shield?
          shield_bonus = ItemArmorPropsMapper.shield_bonus_from_item(shield_item.item)
        elsif defined?(Item)
          sk = normalize_index(shield_item)
          si = Item.find_by(api_index: sk)
          shield_bonus = ItemArmorPropsMapper.shield_bonus_from_item(si) if si&.shield?
        end
        ac += shield_bonus
        source = "#{source} + Escudo"
      end

      {
        ac: ac,
        source: source,
        armor_category: armor_category,
        armor_equipped: armor_category != 'none',
        stealth_disadvantage: stealth_disadvantage,
        speed_penalty: speed_penalty,
        str_requirement: armor_data ? armor_data[:str_req] : nil
      }
    end

    # SheetItem.category pode vir em EN (`weapon`) ou PT-BR (`Armas`) quando a bolsa grava a categoria de UI.
    def sheet_item_weapon_category?(category)
      c = category.to_s.downcase.strip
      return true if c.include?('weapon')
      return true if c == 'armas' || c == 'arma'

      false
    end

    # MagicItem#category — escudo para empilhamento de bônus de CA tipado (escudo vs mágico).
    def magic_item_shield_category?(category)
      c = category.to_s.downcase
      c.include?('shield') || c.include?('escudo')
    end

    def is_weapon?(item)
      return false unless item
      key = normalize_index(item)
      return true if WEAPON_TABLE.key?(key)
      sheet_item_weapon_category?(item.category)
    end

    def normalize_index(item)
      key = (item.respond_to?(:item_index) ? item.item_index : item[:item_index] rescue nil) ||
            (item.respond_to?(:item_name)  ? item.item_name  : item[:item_name]  rescue '') ||
            item.to_s
      key.to_s.downcase.strip
         .gsub(' ', '-')
         .gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    end

    def weapon_props(item)
      return nil unless item
      key = normalize_index(item)

      db_item = item.respond_to?(:item) && item.item&.weapon? ? item.item : nil
      if !db_item && defined?(Item)
        cand = Item.find_by(api_index: key)
        db_item = cand if cand&.weapon?
      end
      if db_item
        mapped = ItemWeaponPropsMapper.from_item(db_item)
        return mapped if mapped.present?
      end

      row = WEAPON_TABLE[key]
      unless row
        props = safe_props(item)
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
          range: props['range'],
          # novos campos (se vierem via props_json):
          cost_cp: props['cost_cp'],
          weight_kg: props['weight_kg']
        }
      end
      row
    end
  end
end
