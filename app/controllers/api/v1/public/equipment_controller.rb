class Api::V1::Public::EquipmentController < ApplicationController
  # GET /api/v1/public/starting_equipment
  # Params: class_id (required), background_id (optional)
  def starting_equipment
    cls = params[:class_id] || params[:klass] || params[:klass_id]
    if cls.to_s.strip.empty?
      return render json: { error: 'class_id is required' }, status: :bad_request
    end

    data = StartingEquipmentService.resolve(class_id: cls, background_id: params[:background_id])
    if data[:error]
      render json: data, status: :bad_request
    else
      render json: data, status: :ok
    end
  end
  # GET /api/v1/public/equipment_profile
  # Params: sheet_id OR character_id (usará a ficha mais recente do personagem)
  def profile
    sheet = nil
    begin
      if params[:sheet_id].present?
        sheet = Sheet.find_by(id: params[:sheet_id])
      elsif params[:character_id].present?
        sheet = Sheet.where(character_id: params[:character_id]).order(id: :desc).first
      end
    rescue; end

    if sheet
      armor = EquipmentRules.allowed_armor_categories(sheet).to_a
      weapon = EquipmentRules.allowed_weapon_profile(sheet)
      render json: {
        armor_categories: armor,
        weapon_categories: weapon[:cats].to_a,
        weapon_properties: weapon[:props].to_a,
        weapon_items: weapon[:items].to_a,
      }, status: :ok
    else
      render json: { error: 'sheet not found or not provided' }, status: :bad_request
    end
  end

  # GET /api/v1/public/equipment/:index
  def show
    idx = (params[:id] || params[:index]).to_s.downcase
    it = defined?(Item) ? Item.find_by(api_index: idx) : nil
    return render json: { error: 'not available' }, status: :not_found unless it
    render json: db_equipment(idx), status: :ok
  end

  # GET /api/v1/public/equipment_categories/:index
  def categories
    idx = (params[:id] || params[:index]).to_s.downcase
    items = items_for_category_from_db(idx)
    details = items.map { |it| build_equipment_from_item(it) }.compact
    render json: { index: idx, name: idx.tr('-', ' ').capitalize, equipment: details }, status: :ok
  end

  # GET /api/v1/public/weapon_properties/:index
  def weapon_properties
    idx = (params[:id] || params[:index]).to_s.downcase
    return render json: { error: 'not available' }, status: :not_found unless defined?(Item)

    weapons = Item.where(kind: 'weapon')
    matched = weapons.select do |it|
      p = (it.props || {})
      props = Array(p['properties']).map { |v| v.to_s.downcase }
      hands = (p['hands'] || 1).to_i
      type  = p['type'].to_s.downcase
      case idx
      when 'finesse' then props.include?('finesse')
      when 'light', 'leve' then props.include?('light')
      when 'heavy', 'pesada' then props.include?('heavy')
      when 'reach', 'alcance' then props.include?('reach')
      when 'loading', 'carregamento' then props.include?('loading')
      when 'special', 'especial' then props.include?('special')
      when 'thrown', 'arremesso' then props.include?('thrown')
      when 'two-handed', 'duas-maos' then hands == 2 && !props.include?('versatile')
      when 'versatile', 'versatil' then props.include?('versatile')
      when 'ammunition', 'municao' then type == 'ranged' && !props.include?('thrown')
      else false
      end
    end

    return render json: { error: 'not available' }, status: :not_found if matched.empty?

    render json: {
      index: idx,
      name: weapon_property_name(idx),
      desc: weapon_property_desc(idx),
      url: "/api/v1/public/weapon_properties/#{idx}",
      weapons: matched.map { |it| { index: it.api_index, name: it.name, url: "/api/v1/public/equipment/#{it.api_index}" } }
    }, status: :ok
  end

  # GET /api/v1/public/equipment_list/:category
  # Retorna lista paginada de equipamentos com detalhes incluídos
  def equipment_list
    category = params[:category].to_s.downcase
    page = params[:page].to_i.positive? ? params[:page].to_i : 1
    per_page = 20
    offset = (page - 1) * per_page

    # Buscar equipamentos da categoria (apenas DB) — records `Item`, não strings.
    items_in_category = items_for_category_from_db(category)
    return render json: { error: 'Category not found' }, status: :not_found if items_in_category.empty?

    paginated_items = items_in_category[offset, per_page]
    total_count = items_in_category.length
    total_pages = (total_count.to_f / per_page).ceil

    # Serializar cada record (db_equipment espera api_index string; aqui já temos o Item)
    equipment_details = paginated_items.map { |it| build_equipment_from_item(it) }.compact

    render json: {
      equipment: equipment_details,
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: per_page,
        has_next: page < total_pages,
        has_prev: page > 1
      }
    }, status: :ok
  end

  private
  # Lista itens (records) para a categoria solicitada, vindos do banco
  def items_for_category_from_db(idx)
    return [] unless defined?(Item)
    key = normalize_category_idx(idx)
    case key
    when :weapons_simple
      Item.where(kind: 'weapon', category: 'simple').order(:api_index).to_a
    when :weapons_martial
      Item.where(kind: 'weapon', category: 'martial').order(:api_index).to_a
    when :armor_light
      Item.where(kind: 'armor', category: 'light').order(:api_index).to_a
    when :armor_medium
      Item.where(kind: 'armor', category: 'medium').order(:api_index).to_a
    when :armor_heavy
      Item.where(kind: 'armor', category: 'heavy').order(:api_index).to_a
    when :armor_all
      Item.where(kind: 'armor').order(:api_index).to_a
    when :shields
      Item.where(kind: 'shield').order(:api_index).to_a
    when :ammunition
      Item.where(kind: 'ammunition').order(:api_index).to_a
    when :gear
      Item.where(kind: 'gear').order(:api_index).to_a
    when :packs
      Item.where(kind: 'pack').order(:api_index).to_a
    when :tools
      Item.where(kind: 'tool').order(:api_index).to_a
    when :consumables
      Item.where(kind: 'consumable').order(:api_index).to_a
    else
      []
    end
  end

  def normalize_category_idx(idx)
    s = idx.to_s.downcase
    s = s.parameterize
    return :weapons_simple  if %w[simple-weapons armas-simples weapon-simple weapons-simple].include?(s)
    return :weapons_martial if %w[martial-weapons armas-marciais weapon-martial weapons-martial].include?(s)
    return :armor_light     if %w[light-armor armaduras-leves armor-light].include?(s)
    return :armor_medium    if %w[medium-armor armaduras-medias armor-medium].include?(s)
    return :armor_heavy     if %w[heavy-armor armaduras-pesadas armor-heavy].include?(s)
    return :armor_all       if %w[armor armaduras].include?(s)
    return :shields         if %w[shields escudos shield].include?(s)
    return :ammunition      if %w[ammunition municoes].include?(s)
    return :gear            if %w[adventuring-gear gear equipamentos utilidades equipment-gear].include?(s)
    return :packs           if %w[equipment-packs packs mochilas].include?(s)
    return :tools           if %w[tools ferramentas instruments-misc].include?(s)
    return :consumables     if %w[consumables consumivel consumiveis].include?(s)
    return :none            if s == 'none'
    nil
  end

  def cp_to_cost_hash(cp)
    # Expressa em po por padrão; mantém compatibilidade com front atual
    po = (cp.to_f / 100.0)
    { quantity: po.round(2), unit: 'gp' }
  end

  # Constrói JSON de um record Item
  def build_equipment_from_item(it)
    return nil unless it
    case it.kind
    when 'weapon'
      wp = it.props || {}
      props = []
      props << 'ammunition' if wp['type'] == 'ranged' && !wp['thrown']
      %w[finesse light heavy loading reach special thrown versatile two-handed].each do |p|
        props << p if wp[p]
      end
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      weight_kg = (defined?(EquipmentRules) ? EquipmentRules.item_weight_kg(it) : nil) rescue nil
      return {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: 'weapon', name: 'Weapon' },
        weapon_category: it.category.to_s,
        weapon_range: wp['type'] == 'ranged' ? 'Ranged' : 'Melee',
        damage: wp['damage_die'].to_s.empty? ? nil : { damage_dice: wp['damage_die'] },
        two_handed_damage: wp['versatile_die'] ? { damage_dice: wp['versatile_die'] } : nil,
        range: wp['range'] ? { normal: wp['range'].to_s.split('/').first.to_i, long: wp['range'].to_s.split('/').last.to_i } : nil,
        properties: props.map { |p| { index: p, name: weapon_property_name(p), url: "/api/v1/public/weapon_properties/#{p}" } },
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_kg,
        url: "/api/v1/public/equipment/#{it.api_index}"
      }.compact
    when 'armor'
      ap = it.props || {}
      ac = { base: ap['ac_base'], dex_bonus: !ap['dex_cap'].to_i.zero?, max_bonus: ap['dex_cap'] }
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      weight_kg = (defined?(EquipmentRules) ? EquipmentRules.item_weight_kg(it) : nil) rescue nil
      return {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: it.category.to_s.capitalize,
        armor_class: ac,
        str_minimum: ap['str_req'],
        stealth_disadvantage: !!ap['stealth_dis'],
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_kg,
        url: "/api/v1/public/equipment/#{it.api_index}"
      }.compact
    when 'shield'
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      weight_kg = (defined?(EquipmentRules) ? EquipmentRules.item_weight_kg(it) : nil) rescue nil
      return {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: 'Shield',
        armor_class: { base: 2, dex_bonus: false },
        stealth_disadvantage: false,
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_kg,
        url: "/api/v1/public/equipment/#{it.api_index}"
      }
    when 'gear', 'pack', 'tool', 'consumable', 'book', 'magic_item', 'ammunition'
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      weight_kg = (defined?(EquipmentRules) ? EquipmentRules.item_weight_kg(it) : nil) rescue nil
      props = it.props || {}
      category_index, category_name = case it.kind
      when 'pack'
        ['equipment-packs', 'Equipment Pack']
      when 'tool'
        ['tools', 'Tools']
      when 'consumable'
        ['consumables', 'Consumables']
      when 'magic_item'
        ['magic-items', 'Magic Items']
      when 'ammunition'
        ['ammunition', 'Ammunition']
      else
        ['adventuring-gear', 'Adventuring Gear']
      end
      {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: category_index, name: category_name },
        gear_category: it.category,
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_kg,
        description: it.description,
        contents: props['contents'] || props[:contents],
        url: "/api/v1/public/equipment/#{it.api_index}"
      }.compact
    else
      nil
    end
  end

  # DB-first equipment lookup por índice
  def db_equipment(idx)
    key = EquipmentCatalog.normalize_index(idx) rescue idx
    return nil unless defined?(Item)
    it = Item.find_by(api_index: key)
    build_equipment_from_item(it)
  end

  def weapon_property_name(idx)
    names = {
      'finesse' => 'Finesse',
      'leve' => 'Leve', 'light' => 'Light',
      'pesada' => 'Pesada', 'heavy' => 'Heavy',
      'alcance' => 'Alcance', 'reach' => 'Reach',
      'carregamento' => 'Carregamento', 'loading' => 'Loading',
      'especial' => 'Especial', 'special' => 'Special',
      'arremesso' => 'Arremesso', 'thrown' => 'Thrown',
      'duas-maos' => 'Duas Mãos', 'two-handed' => 'Two-Handed',
      'versatil' => 'Versátil', 'versatile' => 'Versatile',
      'municao' => 'Munição', 'ammunition' => 'Ammunition'
    }
    names[idx] || idx.to_s
  end

  def weapon_property_desc(idx)
    # Minimal helpful descriptions in pt-BR; can be expanded later
    descs = {
      'finesse' => ['Você pode usar seu modificador de Destreza para jogadas de ataque e dano.'],
      'light' => ['Arma leve; adequada para combate com duas armas.'],
      'leve' => ['Arma leve; adequada para combate com duas armas.'],
      'heavy' => ['Criaturas Pequenas sofrem desvantagem nas jogadas de ataque.'],
      'pesada' => ['Criaturas Pequenas sofrem desvantagem nas jogadas de ataque.'],
      'reach' => ['Seu alcance com esta arma aumenta em 1,5 m (5 pés).'],
      'alcance' => ['Seu alcance com esta arma aumenta em 1,5 m (5 pés).'],
      'loading' => ['Você só pode efetuar um ataque com esta arma por Ação/ação bônus, independentemente do total de ataques.'],
      'carregamento' => ['Você só pode efetuar um ataque com esta arma por Ação/ação bônus, independentemente do total de ataques.'],
      'special' => ['Esta arma possui regras especiais; veja a descrição específica da arma.'],
      'especial' => ['Esta arma possui regras especiais; veja a descrição específica da arma.'],
      'thrown' => ['Você pode arremessar a arma para realizar um ataque à distância.'],
      'arremesso' => ['Você pode arremessar a arma para realizar um ataque à distância.'],
      'two-handed' => ['Você precisa de duas mãos para empunhar esta arma.'],
      'duas-maos' => ['Você precisa de duas mãos para empunhar esta arma.'],
      'versatile' => ['Pode ser usada com uma ou duas mãos; dano maior com duas mãos.'],
      'versatil' => ['Pode ser usada com uma ou duas mãos; dano maior com duas mãos.'],
      'ammunition' => ['A arma utiliza munição adequada (setas, virotes, etc.).'],
      'municao' => ['A arma utiliza munição adequada (setas, virotes, etc.).']
    }
    descs[idx] || []
  end

end
