class MagicItemRules
  # Aggregates effects of equipped magic items and returns a hash with modifiers.
  #
  # Result structure (estendida em Fase 2):
  # {
  #   ac_bonus: Integer,
  #   notes: Array<String>,
  #   weapon_mods: {
  #     main_hand: { attack: Integer, damage: Integer, is_magical: Boolean },
  #     off_hand:  { attack: Integer, damage: Integer, is_magical: Boolean }
  #   },
  #   resistances:        Array<String>,        # ex: ["fogo", "frio"]
  #   damage_immunities:  Array<String>,
  #   damage_vulnerabilities: Array<String>,
  #   condition_immunities: Array<String>,
  #   save_advantages:    Array<String>,        # ability codes: ["wis","cha"]
  #   skill_advantages:   Array<String>,
  #   ability_bonuses:    { "str" => Integer }, # +N flat
  #   ability_sets:       { "str" => Integer }, # set to N (caps); só aplica se maior
  #   speed_bonus:        Integer,              # ft
  #   passive_features:   [{ source:, name:, desc: }],
  #   sources_by_effect:  Hash                  # debug/breakdown
  # }
  EFFECT_DEFAULTS = {
    ac_bonus: 0,
    notes: [],
    resistances: [],
    damage_immunities: [],
    damage_vulnerabilities: [],
    condition_immunities: [],
    save_advantages: [],
    skill_advantages: [],
    ability_bonuses: {},
    ability_sets: {},
    speed_bonus: 0,
    passive_features: [],
  }.freeze

  def initialize(sheet, equipment: nil)
    @sheet = sheet
    @equipment = equipment || EquipmentProfileService.new(sheet).call
  end

  def call
    eq = @equipment || {}
    equipped = eq[:equipped] || {}
    mh = equipped[:main_hand]
    oh = equipped[:off_hand]
    armor = equipped[:armor]
    shield = equipped[:shield]

    res = EFFECT_DEFAULTS.deep_dup.merge(weapon_mods: base_mods, sources_by_effect: {})

    # ── Weapon mods (mão principal/secundária)
    if mh
      mh_mods = weapon_bonus_for(mh)
      res[:notes].concat(Array(mh_mods.delete(:notes)))
      res[:weapon_mods][:main_hand] = merge_mods(res[:weapon_mods][:main_hand], mh_mods)
    end
    if oh
      oh_mods = weapon_bonus_for(oh)
      res[:notes].concat(Array(oh_mods.delete(:notes)))
      res[:weapon_mods][:off_hand]  = merge_mods(res[:weapon_mods][:off_hand],  oh_mods)
    end

    # ── AC (typed stacking: sum of max per type)
    ac_by_type = Hash.new { |h,k| h[k] = [] }
    [armor, shield].compact.each do |part|
      ac_b = ac_bonuses_for(part)
      ac_b.each { |t, v| ac_by_type[t] << v.to_i }
    end
    res[:ac_bonus] = ac_by_type.sum { |type, arr| arr.max.to_i }

    # ── Accessories (Fase 2.1): ring/amulet/cloak/boots/helmet/gloves/belt
    # Acessórios também podem conceder bônus de AC (manto +1, anel de
    # proteção +1, etc.), por isso entram no cálculo de AC tipado também.
    accessories = (equipped[:accessories] || {}).values
    accessories.each do |part|
      ac_b = ac_bonuses_for(part)
      ac_b.each { |t, v| ac_by_type[t] << v.to_i }
    end
    # Recalcula AC tipado considerando accessories
    res[:ac_bonus] = ac_by_type.sum { |_type, arr| arr.max.to_i }

    # ── Generic effects (resistances, advantages, attribute bonuses, speed, passives)
    # Aplicado sobre TODOS os itens equipados (qualquer slot, incluindo accessories).
    ([mh, oh, armor, shield] + accessories).compact.each do |part|
      mi = find_magic_item_for(part)
      next unless mi
      apply_generic_effects!(res, mi)
    end

    res
  end

  private

  def base_mods
    { main_hand: { attack: 0, damage: 0, is_magical: false }, off_hand: { attack: 0, damage: 0, is_magical: false } }
  end

  def merge_mods(a, b)
    return a unless b
    out = a.dup
    out[:attack] = a[:attack].to_i + b[:attack].to_i
    out[:damage] = a[:damage].to_i + b[:damage].to_i
    out[:is_magical] = a[:is_magical] || b[:is_magical]
    out
  end

  # Returns a hash of { type => value } for AC bonuses to allow typed stacking
  def ac_bonuses_for(item)
    mi = find_magic_item_for(item)
    return {} unless mi

    res = Hash.new(0)
    # Legacy bonuses
    b = (mi.bonuses || {})
    legacy = (b['ac'] || b[:ac] || 0).to_i
    if legacy != 0
      default_type = EquipmentRules.magic_item_shield_category?(mi.category) ? 'escudo' : 'magico'
      res[default_type] = [res[default_type].to_i, legacy].max
    end

    # Effects-based bonuses
    Array(mi.try(:effects)).each do |eff|
      next unless eff.is_a?(Hash)
      kind = (eff['kind'] || eff[:kind]).to_s
      case kind
      when 'ac_bonus'
        val = (eff['value'] || eff[:value]).to_i
        t   = (eff['type']  || eff[:type]).to_s.presence || (EquipmentRules.magic_item_shield_category?(mi.category) ? 'escudo' : 'magico')
        res[t] = [res[t].to_i, val].max
      when 'set_ac_base'
        # Not applied here; would require overriding base AC formula upstream.
        # Could add a note for UI or future handling.
      end
    end

    res
  end

  def weapon_bonus_for(item)
    return { attack: 0, damage: 0, is_magical: false, notes: [] } unless item
    mi = find_magic_item_for(item)
    return { attack: 0, damage: 0, is_magical: false, notes: [] } unless mi

    attack = 0
    damage = 0
    is_magical = false
    notes = []

    # Legacy bonuses
    b = (mi.bonuses || {})
    attack += (b['attack'] || b[:attack] || 0).to_i
    damage += (b['damage'] || b[:damage] || 0).to_i
    is_magical ||= (attack != 0 || damage != 0)

    # Effects-based bonuses
    Array(mi.try(:effects)).each do |eff|
      next unless eff.is_a?(Hash)
      kind = (eff['kind'] || eff[:kind]).to_s
      case kind
      when 'attack_bonus'
        attack += (eff['value'] || eff[:value] || 0).to_i
        is_magical ||= (eff['type'] || eff[:type]).to_s == 'magico' || attack != 0
      when 'damage_bonus_flat'
        damage += (eff['value'] || eff[:value] || 0).to_i
        is_magical ||= (eff['type'] || eff[:type]).to_s == 'magico' || damage != 0
      when 'damage_bonus_dice'
        dice = (eff['dice'] || eff[:dice]).to_s
        dtype = (eff['damage_type'] || eff[:damage_type]).to_s
        notes << "+#{dice} #{dtype}".strip
        is_magical = true if dice.present?
      when 'weapon_is_magical'
        is_magical = true
      end
    end

    { attack: attack, damage: damage, is_magical: is_magical, notes: notes }
  end

  ABILITY_KEYS = %w[str dex con int wis cha].freeze

  def apply_generic_effects!(res, mi)
    src = mi.respond_to?(:slug) ? mi.slug : mi.try(:name)
    Array(mi.try(:effects)).each do |eff|
      next unless eff.is_a?(Hash)
      kind = (eff['kind'] || eff[:kind]).to_s
      case kind
      when 'resistance'
        types = Array(eff['damage_types'] || eff[:damage_types] || eff['damage_type'] || eff[:damage_type])
        types.flatten.compact.each { |t| res[:resistances] << t.to_s.downcase }
      when 'damage_immunity'
        Array(eff['damage_types'] || eff[:damage_types] || eff['damage_type'] || eff[:damage_type]).each do |t|
          res[:damage_immunities] << t.to_s.downcase
        end
      when 'damage_vulnerability'
        Array(eff['damage_types'] || eff[:damage_types] || eff['damage_type'] || eff[:damage_type]).each do |t|
          res[:damage_vulnerabilities] << t.to_s.downcase
        end
      when 'condition_immunity'
        Array(eff['conditions'] || eff[:conditions] || eff['condition'] || eff[:condition]).each do |c|
          res[:condition_immunities] << c.to_s.downcase
        end
      when 'save_advantage'
        Array(eff['abilities'] || eff[:abilities] || eff['ability'] || eff[:ability]).each do |a|
          ab = a.to_s.downcase
          res[:save_advantages] << ab if ABILITY_KEYS.include?(ab)
        end
      when 'skill_advantage'
        Array(eff['skills'] || eff[:skills] || eff['skill'] || eff[:skill]).each do |s|
          res[:skill_advantages] << s.to_s.downcase
        end
      when 'ability_bonus'
        ab = (eff['ability'] || eff[:ability]).to_s.downcase
        v  = (eff['value']   || eff[:value]).to_i
        if ABILITY_KEYS.include?(ab) && v != 0
          res[:ability_bonuses][ab] = (res[:ability_bonuses][ab] || 0) + v
        end
      when 'ability_set', 'set_ability'
        ab = (eff['ability'] || eff[:ability]).to_s.downcase
        v  = (eff['value']   || eff[:value]).to_i
        if ABILITY_KEYS.include?(ab) && v > 0
          # Mantém o maior set quando há múltiplos itens (ex.: 2 manoplas)
          cur = res[:ability_sets][ab].to_i
          res[:ability_sets][ab] = [cur, v].max
        end
      when 'speed_bonus'
        v = (eff['value'] || eff[:value]).to_i
        # Para speed, somamos untyped (regra simples; refinar para typed em fase futura)
        res[:speed_bonus] = res[:speed_bonus].to_i + v if v != 0
      when 'passive_feature'
        res[:passive_features] << {
          source: src,
          name: (eff['name'] || eff[:name]).to_s,
          desc: (eff['desc'] || eff[:desc]).to_s,
        }
      end
    end
    res[:resistances].uniq!
    res[:damage_immunities].uniq!
    res[:damage_vulnerabilities].uniq!
    res[:condition_immunities].uniq!
    res[:save_advantages].uniq!
    res[:skill_advantages].uniq!
  end

  def find_magic_item_for(item)
    # Strategy:
    # 1) explicit slug in props
    slug = (item[:props] || {})['magic_item_slug'] rescue nil
    begin
      return MagicItem.find_by(slug: slug) if slug.present?
    rescue; end

    # 2) attempt by normalized index or name
    idx = normalize(item[:index] || item[:name] || '')
    begin
      return MagicItem.find_by(slug: idx)
    rescue; end

    # 3) fuzzy by name (downcased)
    name = (item[:name] || '').to_s.downcase
    begin
      return MagicItem.where('lower(name) = ?', name).first
    rescue; end
    nil
  end

  def normalize(text)
    I18n.transliterate(text.to_s).downcase.strip.gsub(/[^a-z0-9\-\s]/,'').gsub(/\s+/,'-').gsub(/-+/,'-')
  end
end
