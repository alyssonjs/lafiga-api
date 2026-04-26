class FightingStyleRules
  # Resolve um nome livre/legado para o nome canonico em ClassRules::FIGHTING_STYLES.
  # Retorna a string canonica se for um valor valido (direto ou via alias) ou nil
  # se for desconhecido. Usado para validar imports e normalizar inputs do wizard.
  def self.canonicalize(name)
    return nil if name.blank?
    str = name.to_s.strip
    return str if ClassRules::FIGHTING_STYLES.include?(str)
    aliased = ClassRules::FIGHTING_STYLE_ALIASES[str]
    return aliased if aliased
    # case-insensitive fallback
    direct = ClassRules::FIGHTING_STYLES.find { |s| s.casecmp?(str) }
    return direct if direct
    fuzzy = ClassRules::FIGHTING_STYLE_ALIASES.find { |k, _| k.casecmp?(str) }
    fuzzy&.last
  end

  # Computes active Fighting Style modifiers based on current equipment and class choices
  # Returns a hash:
  # {
  #   ac_bonus: Integer,
  #   weapon_mods: {
  #     main_hand: { attack: Integer, damage: Integer, offhand_add_ability: Boolean },
  #     off_hand:  { attack: Integer, damage: Integer, offhand_add_ability: Boolean }
  #   },
  #   notes: Array<String>,
  #   active_styles: Array<String>
  # }
  def initialize(sheet, equipment: nil)
    @sheet = sheet
    @equipment = equipment || EquipmentProfileService.new(sheet).call
  end

  def call
    meta = (@sheet.metadata || {})
    choices = (meta.dig('class_choices') || {})
    top_style = choices['fighting_style'] || choices.dig('fighting_style')
    # per-level picks may include fighting_style at required level (Champion 10, etc.)
    per_level = choices['per_level'] || {}
    per_styles = per_level.values.filter_map { |row| row&.dig('fighting_style') || row&.dig(:fighting_style) }.compact
    # Collect all styles (avoid duplicates). Wizard/API gravam fighting_style como Array
    # e.g. ["fs-archery"] — Array#to_s vira "[\"fs-archery\"]" e quebrava o case /regex/.
    raw_styles = []
    raw_styles.concat(flatten_fighting_style_pick(top_style)) if top_style.present?
    per_styles.each { |s| raw_styles.concat(flatten_fighting_style_pick(s)) if s.present? }
    style_names = raw_styles.map(&:strip).reject(&:empty?).uniq

    result = { ac_bonus: 0, weapon_mods: { main_hand: base_mods, off_hand: base_mods }, notes: [], active_styles: [] }
    return result if style_names.empty?

    mh = @equipment.dig(:equipped, :main_hand)
    oh = @equipment.dig(:equipped, :off_hand)
    armor = @equipment.dig(:equipped, :armor)

    # Normalize props for weapons
    mhp = mh ? EquipmentRules.weapon_props(mh) : nil
    ohp = oh ? EquipmentRules.weapon_props(oh) : nil
    off_is_weapon = EquipmentRules.is_weapon?(oh)

    style_names.uniq.each do |style_name|
      case style_name.downcase
      when /defesa|defense/
        # +1 AC when wearing any armor
        if armor
          result[:ac_bonus] = (result[:ac_bonus].to_i + 1)
          result[:active_styles] << 'Defesa'
        end
      when /arquearia|arqueria|archery|tiro\s+com\s+arco|fs[-_]archery/
        # +2 to attack rolls with ranged weapons (main hand)
        # Wizard PT grava "Tiro com Arco" / fs-archery; antes só casava "Arquearia".
        if mhp && mhp[:type] == 'ranged'
          cur = result[:weapon_mods][:main_hand]
          result[:weapon_mods][:main_hand] = cur.merge(attack: (cur[:attack] || 0) + 2)
          result[:active_styles] << 'Arquearia'
        end
      when /duelos|duelo|dueling/
        # +2 damage with a one‑handed weapon and no other weapon (shield allowed)
        one_handed = mhp && (mhp[:hands].to_i == 1 || mhp[:versatile])
        no_other_weapon = !off_is_weapon
        if one_handed && no_other_weapon
          cur = result[:weapon_mods][:main_hand]
          result[:weapon_mods][:main_hand] = cur.merge(damage: (cur[:damage] || 0) + 2)
          result[:active_styles] << 'Duelos'
        end
      when /duas\s*armas|two[- ]weapon/
        # Add ability modifier to off‑hand damage when two‑weapon fighting
        if off_is_weapon
          cur = result[:weapon_mods][:off_hand]
          result[:weapon_mods][:off_hand] = cur.merge(offhand_add_ability: true)
          result[:active_styles] << 'Combate com Duas Armas'
        end
      when /grande\s*arma|great\s*weapon/
        # Informational note: re‑roll 1s and 2s on damage dice with two‑handed/versatile used two‑handed
        two_handed = mhp && (mhp[:hands].to_i == 2 || mhp[:versatile])
        if two_handed
          result[:notes] << 'Grande Arma: re‑role 1 e 2 no dado de dano.'
          result[:active_styles] << 'Grande Arma'
        end
      when /prote(c|ç)ão|protecao|protection/
        # Protection imposes disadvantage to attacker (requires shield) — informational only
        if @equipment.dig(:equipped, :shield)
          result[:notes] << 'Proteção: pode impor desvantagem a ataque adjacente (requer escudo).'
          result[:active_styles] << 'Proteção'
        end
      end
    end

    result
  end

  private

  def flatten_fighting_style_pick(pick)
    case pick
    when nil, '' then []
    when Hash
      v = (pick['name'] || pick[:name] || pick['id'] || pick[:id]).to_s.strip
      v.present? ? [v] : []
    when Array
      pick.flat_map { |x| flatten_fighting_style_pick(x) }
    else
      s = pick.to_s.strip
      s.present? ? [s] : []
    end
  end

  def base_mods
    { attack: 0, damage: 0, offhand_add_ability: false }
  end
end
