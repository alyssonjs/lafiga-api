class FightingStyleRules
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
    # per-level picks may include fighting_style at required level
    per_level = choices['per_level'] || {}
    per_styles = per_level.values.map { |row| row['fighting_style'] || row[:fighting_style] }.compact
    style = (per_styles.find(&:present?) || top_style)
    # normalize to string name
    style_name = case style
                 when Hash then (style['name'] || style[:name] || style['id'] || style[:id])
                 else style
                 end
    style_name = style_name.to_s

    result = { ac_bonus: 0, weapon_mods: { main_hand: base_mods, off_hand: base_mods }, notes: [], active_styles: [] }
    return result if style_name.empty?

    mh = @equipment.dig(:equipped, :main_hand)
    oh = @equipment.dig(:equipped, :off_hand)
    armor = @equipment.dig(:equipped, :armor)

    # Normalize props for weapons
    mhp = mh ? EquipmentRules.weapon_props(mh) : nil
    ohp = oh ? EquipmentRules.weapon_props(oh) : nil
    off_is_weapon = EquipmentRules.is_weapon?(oh)

    case style_name.downcase
    when /defesa|defense/
      # +1 AC when wearing any armor
      if armor
        result[:ac_bonus] = 1
        result[:active_styles] << 'Defesa'
      end
    when /arquearia|archery/
      # +2 to attack rolls with ranged weapons (main hand)
      if mhp && mhp[:type] == 'ranged'
        result[:weapon_mods][:main_hand] = base_mods.merge(attack: 2)
        result[:active_styles] << 'Arquearia'
      end
    when /duelos|duelo|dueling/
      # +2 damage with a one‑handed weapon and no other weapon (shield allowed)
      one_handed = mhp && (mhp[:hands].to_i == 1 || mhp[:versatile])
      no_other_weapon = !off_is_weapon
      if one_handed && no_other_weapon
        result[:weapon_mods][:main_hand] = base_mods.merge(damage: 2)
        result[:active_styles] << 'Duelos'
      end
    when /duas\s*armas|two[- ]weapon/
      # Add ability modifier to off‑hand damage when two‑weapon fighting
      if off_is_weapon
        result[:weapon_mods][:off_hand] = base_mods.merge(offhand_add_ability: true)
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

    result
  end

  private

  def base_mods
    { attack: 0, damage: 0, offhand_add_ability: false }
  end
end

