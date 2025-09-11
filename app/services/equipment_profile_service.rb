class EquipmentProfileService
  def initialize(sheet)
    @sheet = sheet
  end

  def call
    items = SheetItem.where(sheet_id: @sheet.id)
    equipped = items.select { |it| it.equipped }
    armor = equipped.find { |it| (it.slot == 'armor') || armor_like?(it) }
    shield = equipped.find { |it| (it.slot == 'shield') || EquipmentRules.is_shield?(it) }

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
      props: it.props_json
    }
  end

  def armor_like?(it)
    idx = EquipmentRules.normalize_index(it)
    EquipmentRules::ARMOR_TABLE.key?(idx)
  end
end

