class EquipmentProfileService
  def initialize(sheet)
    @sheet = sheet
  end

  def call
    items = SheetItem.where(sheet_id: @sheet.id)
    equipped = items.select { |it| it.equipped }
    armor = equipped.find { |it| (it.slot == 'armor') || armor_like?(it) }
    shield = equipped.find { |it| (it.slot == 'shield') || EquipmentRules.is_shield?(it) }
    # Heurística de mãos: prioriza slots explícitos; caso contrário, escolhe a melhor opção
    weapon_items = equipped.select { |it| it.category.to_s.downcase.include?('weapon') }
    main_hand = equipped.find { |it| it.slot == 'main_hand' }
    off_hand  = equipped.find { |it| it.slot == 'off_hand' }
    unless main_hand
      # preferir arma de 2 mãos/versátil como principal, se existir
      two_handed = weapon_items.find do |it|
        p = EquipmentRules.weapon_props(it)
        p && (p[:hands].to_i == 2 || p[:versatile])
      end
      main_hand = two_handed || weapon_items.first
      # evite conflito com off_hand explícita
      if off_hand && main_hand && main_hand.id == off_hand.id
        main_hand = (weapon_items - [off_hand]).first
      end
    end
    unless off_hand
      # escolher segunda arma, se houver, preferindo 'light'
      candidates = (weapon_items - [main_hand])
      light = candidates.find { |it| (EquipmentRules.weapon_props(it) || {})[:light] }
      off_hand = light || candidates.first
    end

    ac = EquipmentRules.ac_for(sheet: @sheet, armor_item: armor, shield_item: shield)

    # Carry weight (best-effort if weight known in props_json)
    total_weight = items.sum { |it| (it.props_json || {})['weight_kg'].to_f * (it.quantity || 1).to_i rescue 0.0 }
    str = @sheet.str.to_i
    max_kg = (str * 7.5).round(2)
    overloaded = total_weight > max_kg

    {
      inventory: items.map { |it| as_json(it) },
      equipped: {
        armor: armor ? as_json(armor) : nil,
        shield: shield ? as_json(shield) : nil,
        main_hand: main_hand ? as_json(main_hand) : nil,
        off_hand: off_hand ? as_json(off_hand) : nil,
      },
      ac: ac,
      carry: { total_kg: total_weight.round(2), max_kg: max_kg, overloaded: overloaded }
    }
  end

  private

  def as_json(it)
    {
      id: it.id,
      index: it.item_index,
      name: it.item_name,
      category: it.category,
      quantity: it.quantity,
      equipped: it.equipped,
      slot: it.slot,
      source: it.source,
      props: it.props_json,
      weapon_props: EquipmentRules.weapon_props(it)
    }
  end

  def armor_like?(it)
    idx = EquipmentRules.normalize_index(it)
    EquipmentRules::ARMOR_TABLE.key?(idx)
  end
end
