class MagicItemRules
  # Aggregates effects of equipped magic items and returns a hash with modifiers
  # Result structure (subset used by UI):
  # {
  #   ac_bonus: Integer,
  #   notes: Array<String>,
  #   weapon_mods: {
  #     main_hand: { attack: Integer, damage: Integer, is_magical: Boolean },
  #     off_hand:  { attack: Integer, damage: Integer, is_magical: Boolean }
  #   }
  # }
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

    res = { ac_bonus: 0, notes: [], weapon_mods: base_mods }

    # Apply weapon bonuses (effects aware)
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

    # Armor/shield AC bonuses (typed stacking: sum of max per type)
    ac_by_type = Hash.new { |h,k| h[k] = [] }
    [armor, shield].compact.each do |part|
      ac_b = ac_bonuses_for(part) # => { type => value }
      ac_b.each { |t, v| ac_by_type[t] << v.to_i }
    end
    res[:ac_bonus] = ac_by_type.sum { |type, arr| arr.max.to_i }

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
      default_type = mi.category.to_s.downcase.include?('shield') ? 'escudo' : 'magico'
      res[default_type] = [res[default_type].to_i, legacy].max
    end

    # Effects-based bonuses
    Array(mi.try(:effects)).each do |eff|
      next unless eff.is_a?(Hash)
      kind = (eff['kind'] || eff[:kind]).to_s
      case kind
      when 'ac_bonus'
        val = (eff['value'] || eff[:value]).to_i
        t   = (eff['type']  || eff[:type]).to_s.presence || (mi.category.to_s.downcase.include?('shield') ? 'escudo' : 'magico')
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
