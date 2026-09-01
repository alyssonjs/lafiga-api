class EquipmentProfileService
  def initialize(sheet)
    @sheet = sheet
  end

  def call
    # Eager-load `items` to avoid N+1 em `EquipmentRules.weapon_props` / custo-peso
    # quando cada `SheetItem` resolve o catálogo por `api_index`.
    items = SheetItem.where(sheet_id: @sheet.id).order(:position, :id).includes(:item)
    equipped = items.select { |it| it.equipped }
    armor = equipped.find { |it| (it.slot == 'armor') || armor_like?(it) }
    shield = equipped.find { |it| (it.slot == 'shield') || EquipmentRules.is_shield?(it) }
    # Heurística de mãos: prioriza slots explícitos; caso contrário, escolhe a melhor opção
    weapon_items = equipped.select { |it| EquipmentRules.sheet_item_weapon_category?(it.category) }
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

    # ── Accessories (Fase 2.1) ───────────────────────────────────────
    # Mapa slot → SheetItem para todos os accessory slots equipados.
    # Inclui ring_left/ring_right (até 2 anéis), amulet, cloak, boots,
    # helmet (cabeça), face (rosto), gloves, belt, earrings, braceletes. Usado por MagicItemRules para varrer efeitos.
    accessory_slots = SheetItem::ACCESSORY_SLOTS
    accessories = accessory_slots.each_with_object({}) do |slot_name, acc|
      it = equipped.find { |e| e.slot.to_s == slot_name }
      acc[slot_name.to_sym] = it if it
    end

    ac = EquipmentRules.ac_for(sheet: @sheet, armor_item: armor, shield_item: shield)

    # Carry weight using PHB rules (now in kilograms) with optional variant encumbrance
    #
    # ⚠️ LIVRO, não física. O fator é 2 lb por kg (`EquipmentRules::LB_PER_KG`),
    # que é a mesma conversão do serializer — a espada de 3 lb do PHB pesa 1,5 kg
    # nesta mesa, não 1,36. Usar o fator físico (0,45359237) aqui dava 68,04 kg
    # de capacidade para FOR 10 enquanto a tela mostrava 75, e a CARGA lida de
    # `weight_lb` encolhia 9% — os dois lados da mesma comparação em convenções
    # diferentes, que é como a comparação deixa de querer dizer alguma coisa.
    total_kg = items.sum { |it| weight_kg(it) * (it.quantity || 1).to_i rescue 0.0 }
    equipped_kg = equipped.sum { |it| weight_kg(it) * (it.quantity || 1).to_i rescue 0.0 }
    str = @sheet.str.to_i
    # Capacidades base do PHB: FOR × 15 (carregar) e FOR × 30 (empurrar/arrastar).
    carrying_capacity_kg = lb_to_kg(str * 15).round(2)
    push_drag_lift_kg = lb_to_kg(str * 30).round(2)

    meta = (@sheet.metadata || {})
    # Capacity multipliers from traits/features (e.g., Powerful Build, Aspect of the Beast - Bear)
    begin
      mult = 1
      names = []
      # Race trait names
      rs = meta['race_summary'] || {}
      begin
        trait_keys = Array(rs['traits'])
        if trait_keys.any?
          names += Trait.where(api_index: trait_keys).pluck(:name).map(&:downcase) rescue []
        end
      rescue; end
      # Metadata feats/features text (best-effort)
      begin
        feats_meta = Array(meta['feats'])
        names += feats_meta.map { |f| (f['name'] || f[:name]).to_s.downcase }
      rescue; end
      # Freeform features list that may exist in metadata
      begin
        features = Array(meta['features']).map { |f| (f['name'] || f[:name]).to_s.downcase }
        names += features
      rescue; end
      text = names.join(' | ')
      if text.include?('powerful build') || text.include?('construção poderosa') || text.include?('construcao poderosa')
        mult *= 2
      end
      if text.include?('aspect of the beast') && text.include?('bear')
        mult *= 2
      end
      if text.include?('aspecto da besta') && text.include?('urso')
        mult *= 2
      end
      if mult > 1
        carrying_capacity_kg = (carrying_capacity_kg * mult).round(2)
        push_drag_lift_kg = (push_drag_lift_kg * mult).round(2)
      end
    rescue; end
    use_variant = meta['encumbrance_variant'] || meta['use_variant_encumbrance'] || false
    status = 'normal'
    speed_pen_ft = 0
    disadv = { ability_checks: [], attack: false, saving_throws: [] }
    if use_variant
      enc_kg = lb_to_kg(str * 5)
      heavy_kg = lb_to_kg(str * 10)
      # apply multipliers from above
      begin
        base_capacity_kg = lb_to_kg(str * 15)
        factor = base_capacity_kg > 0 ? (carrying_capacity_kg / base_capacity_kg) : 1.0
        enc_kg *= factor
        heavy_kg *= factor
      rescue; end
      if total_kg > heavy_kg
        status = 'heavily_encumbered'
        speed_pen_ft = 20
        disadv[:ability_checks] = %w[str dex con]
        disadv[:saving_throws] = %w[str dex con]
        disadv[:attack] = true
      elsif total_kg > enc_kg
        status = 'encumbered'
        speed_pen_ft = 10
      end
    else
      status = (total_kg > carrying_capacity_kg) ? 'over_capacity' : 'normal'
    end

    {
      inventory: items.map { |it| as_json(it) },
      equipped: {
        armor: armor ? as_json(armor) : nil,
        shield: shield ? as_json(shield) : nil,
        main_hand: main_hand ? as_json(main_hand) : nil,
        off_hand: off_hand ? as_json(off_hand) : nil,
        accessories: accessories.transform_values { |it| as_json(it) },
      },
      ac: ac,
      carry: {
        total_kg: total_kg.round(2),
        equipped_kg: equipped_kg.round(2),
        capacity_kg: carrying_capacity_kg.round(2),
        push_drag_lift_kg: push_drag_lift_kg.round(2),
        variant: !!use_variant,
        status: status,
        speed_penalty_ft: speed_pen_ft,
        disadvantage: disadv
      }
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

  def weight_lb(it)
    p = (it.props_json || {})
    # Supported keys: weight_lb (preferred), weight_kg, weight (string like "6 lb")
    if p.key?('weight_lb')
      return p['weight_lb'].to_f
    end
    if p.key?('weight_kg')
      return (p['weight_kg'].to_f * 2.20462)
    end
    w = p['weight'] || p['weight_str']
    if w
      m = w.to_s.match(/([0-9]+(?:\.[0-9]+)?)\s*lb/i)
      return m[1].to_f if m
      mk = w.to_s.match(/([0-9]+(?:\.[0-9]+)?)\s*kg/i)
      return (mk[1].to_f * 2.20462) if mk
    end
    0.0
  rescue
    0.0
  end

  # Libras → quilos pela convenção do LIVRO. Uma função e não um literal: eram
  # oito literais iguais, e o que os fez divergir da tela foi exatamente isso.
  def lb_to_kg(lb)
    lb.to_f / EquipmentRules::LB_PER_KG
  end

  def weight_kg(it)
    p = (it.props_json || {})
    return p['weight_kg'].to_f if p.key?('weight_kg')
    if p.key?('weight_lb')
      return lb_to_kg(p['weight_lb'].to_f)
    end
    w = p['weight'] || p['weight_str']
    if w
      # numeric value from catalogs (DnD 5e API uses lb by default)
      if w.is_a?(Numeric)
        return lb_to_kg(w.to_f)
      end
      mk = w.to_s.match(/([0-9]+(?:\.[0-9]+)?)\s*kg/i)
      return mk[1].to_f if mk
      m = w.to_s.match(/([0-9]+(?:\.[0-9]+)?)\s*lb/i)
      return lb_to_kg(m[1].to_f) if m
    end
    0.0
  rescue
    0.0
  end

  def armor_like?(it)
    idx = EquipmentRules.normalize_index(it)
    EquipmentRules::ARMOR_TABLE.key?(idx)
  end
end
