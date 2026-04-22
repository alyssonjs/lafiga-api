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
end

require 'net/http'
require 'uri'

class Api::V1::Public::EquipmentController < ApplicationController
  BASE = 'https://www.dnd5eapi.co'.freeze

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

    # Buscar equipamentos da categoria (apenas DB)
    equipment_indexes = items_for_category_from_db(category)
    return render json: { error: 'Category not found' }, status: :not_found if equipment_indexes.empty?

    # Paginar os índices
    paginated_indexes = equipment_indexes[offset, per_page]
    total_count = equipment_indexes.length
    total_pages = (total_count.to_f / per_page).ceil

    # Buscar detalhes de todos os equipamentos da página atual
    equipment_details = paginated_indexes.map { |index| db_equipment(index) }.compact

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

  def db_equipment_indexes_for_category(category)
    return [] unless defined?(Item)
    case category
    when 'simple-weapons'
      Item.where(kind: 'weapon', category: 'simple').pluck(:api_index)
    when 'martial-weapons'
      Item.where(kind: 'weapon', category: 'martial').pluck(:api_index)
    when 'simple-melee-weapons'
      Item.where(kind: 'weapon').where("(props->>'type') = ? AND category = ?", 'melee', 'simple').pluck(:api_index)
    when 'simple-ranged-weapons'
      Item.where(kind: 'weapon').where("(props->>'type') = ? AND category = ?", 'ranged', 'simple').pluck(:api_index)
    when 'martial-melee-weapons'
      Item.where(kind: 'weapon').where("(props->>'type') = ? AND category = ?", 'melee', 'martial').pluck(:api_index)
    when 'martial-ranged-weapons'
      Item.where(kind: 'weapon').where("(props->>'type') = ? AND category = ?", 'ranged', 'martial').pluck(:api_index)
    when 'armor'
      Item.where(kind: 'armor').pluck(:api_index) + Item.where(kind: 'shield').pluck(:api_index)
    when 'shields'
      Item.where(kind: 'shield').pluck(:api_index)
    when 'ammunition'
      Item.where(kind: 'ammunition').pluck(:api_index)
    when 'consumables'
      Item.where(kind: 'consumable').pluck(:api_index)
    when 'gear'
      Item.where(kind: 'gear').pluck(:api_index)
    when 'equipment-packs', 'packs'
      Item.where(kind: ['pack', 'gear']).where(category: 'pack').pluck(:api_index)
    when 'tools'
      Item.where(kind: 'tool').pluck(:api_index)
    when 'consumables'
      Item.where(kind: 'consumable').pluck(:api_index)
    else
      []
    end
  end

  # Helper para buscar índices de equipamentos por categoria
  def get_equipment_indexes_for_category(category)
    return [] unless defined?(EquipmentRules)
    
    t = if defined?(EquipmentCatalog) && EquipmentCatalog.data['weapons'].present?
      EquipmentCatalog.data['weapons']
    else
      EquipmentRules::WEAPON_TABLE rescue nil
    end
    a = if defined?(EquipmentCatalog) && EquipmentCatalog.data['armors'].present?
      EquipmentCatalog.data['armors']
    else
      EquipmentRules::ARMOR_TABLE rescue nil
    end
    g = if defined?(EquipmentCatalog) && EquipmentCatalog.data['gear'].present?
      EquipmentCatalog.data['gear']
    else
      nil
    end
    pk = if defined?(EquipmentCatalog) && EquipmentCatalog.data['packs'].present?
      EquipmentCatalog.data['packs']
    else
      nil
    end
    tl = if defined?(EquipmentCatalog) && EquipmentCatalog.data['tools'].present?
      EquipmentCatalog.data['tools']
    else
      nil
    end

    case category
    when 'simple-weapons'
      if defined?(EquipmentCatalog) && t.is_a?(Hash) && t.values.first.is_a?(Hash) && t.values.first['category']
        t.select { |_k, v| v['category'] == 'simple' }.map { |k, _| k }
      else
        t&.select { |_k, v| v[:category] == 'simple' }&.map { |k, _| k } || []
      end
    when 'martial-weapons'
      if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['category']
        t.select { |_k, v| v['category'] == 'martial' }.map { |k, _| k }
      else
        t&.select { |_k, v| v[:category] == 'martial' }&.map { |k, _| k } || []
      end
    when 'simple-melee-weapons'
      if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'simple' && v['type'] == 'melee' }.map { |k, _| k }
      else
        t&.select { |_k, v| v[:category] == 'simple' && v[:type] == 'melee' }&.map { |k, _| k } || []
      end
    when 'simple-ranged-weapons'
      if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'simple' && v['type'] == 'ranged' }.map { |k, _| k }
      else
        t&.select { |_k, v| v[:category] == 'simple' && v[:type] == 'ranged' }&.map { |k, _| k } || []
      end
    when 'martial-melee-weapons'
      if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'martial' && v['type'] == 'melee' }.map { |k, _| k }
      else
        t&.select { |_k, v| v[:category] == 'martial' && v[:type] == 'melee' }&.map { |k, _| k } || []
      end
    when 'martial-ranged-weapons'
      if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'martial' && v['type'] == 'ranged' }.map { |k, _| k }
      else
        t&.select { |_k, v| v[:category] == 'martial' && v[:type] == 'ranged' }&.map { |k, _| k } || []
      end
    when 'armor'
      a&.keys || []
    when 'shields'
      (defined?(EquipmentCatalog) ? EquipmentCatalog.shield_indexes : ['shield']) || []
    when 'ammunition'
      # Munições são mais limitadas, retornar lista básica
      ['arrow', 'blowgun-needle', 'crossbow-bolt', 'sling-bullet']
    when 'gear'
      if g.is_a?(Hash)
        g.keys
      else
        Item.where(kind: 'gear').pluck(:api_index)
      end
    when 'equipment-packs'
      if pk.is_a?(Hash)
        pk.keys
      else
        Item.where(kind: ['pack', 'gear']).where(category: 'pack').pluck(:api_index)
      end
    when 'tools'
      if tl.is_a?(Hash)
        tl.keys
      else
        Item.where(kind: 'tool').pluck(:api_index)
      end
    when 'consumables'
      Item.where(kind: 'consumable').pluck(:api_index)
    else
      []
    end
  end

  def fetch_json(path)
    url = URI.join(BASE, path)
    res = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https', read_timeout: 5, open_timeout: 3) do |http|
      req = Net::HTTP::Get.new(url)
      http.request(req)
    end
    return nil unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body) rescue nil
  rescue => e
    Rails.logger.warn("Equipment proxy failed: #{e.class}: #{e.message}")
    nil
  end

  # Build a weapon-property response from our local EquipmentRules table
  def local_weapon_property(idx)
    # Map accepted indexes to a predicate over EquipmentRules::WEAPON_TABLE rows
    predicates = {
      'finesse'     => ->(row) { !!row[:finesse] },
      'leve'        => ->(row) { !!row[:light] }, # alias pt-br
      'light'       => ->(row) { !!row[:light] },
      'pesada'      => ->(row) { !!row[:heavy] }, # alias pt-br
      'heavy'       => ->(row) { !!row[:heavy] },
      'alcance'     => ->(row) { !!row[:reach] }, # alias pt-br
      'reach'       => ->(row) { !!row[:reach] },
      'carregamento'=> ->(row) { !!row[:loading] }, # alias pt-br
      'loading'     => ->(row) { !!row[:loading] },
      'especial'    => ->(row) { !!row[:special] }, # alias pt-br
      'special'     => ->(row) { !!row[:special] },
      'arremesso'   => ->(row) { !!row[:thrown] }, # alias pt-br
      'thrown'      => ->(row) { !!row[:thrown] },
      'duas-maos'   => ->(row) { row[:hands].to_i == 2 && !row[:versatile] }, # alias pt-br
      'two-handed'  => ->(row) { row[:hands].to_i == 2 && !row[:versatile] },
      'versatil'    => ->(row) { !!row[:versatile] }, # alias pt-br
      'versatile'   => ->(row) { !!row[:versatile] },
      'municao'     => ->(row) { row[:type] == 'ranged' && !row[:thrown] }, # alias pt-br
      'ammunition'  => ->(row) { row[:type] == 'ranged' && !row[:thrown] },
    }

    pred = predicates[idx]
    return nil unless pred

    # Prefer YAML catalog; fall back to EquipmentRules
    if defined?(EquipmentCatalog)
      # Build rows from catalog
      catalog_rows = {}
      (EquipmentCatalog.data['weapons'] || {}).each do |k, _|
        row = EquipmentCatalog.weapon_row(k)
        catalog_rows[k] = row if row
      end
      matched = catalog_rows.select { |_k, row| pred.call(row) }
    else
      matched = {}
    end

    if matched.empty? && defined?(EquipmentRules)
      table = EquipmentRules::WEAPON_TABLE rescue {}
      matched = table.select { |_k, row| pred.call(row) }
    end
    return nil if matched.empty?

    {
      index: idx,
      name: weapon_property_name(idx),
      desc: weapon_property_desc(idx),
      url: "/api/v1/public/weapon_properties/#{idx}",
      weapons: matched.map { |k, _| { index: k, name: k.tr('-', ' '), url: "/api/v1/public/equipment/#{k}" } }
    }
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

  # Local equipment show: builds from EquipmentRules weapon/armor tables
  def local_equipment(idx)
    return nil unless defined?(EquipmentRules)
    t = if defined?(EquipmentCatalog) && EquipmentCatalog.data['weapons'].present?
      Hash[(EquipmentCatalog.data['weapons'] || {}).map { |k,_| [k, EquipmentCatalog.weapon_row(k)] }]
    else
      EquipmentRules::WEAPON_TABLE rescue nil
    end
    a = if defined?(EquipmentCatalog) && EquipmentCatalog.data['armors'].present?
      Hash[(EquipmentCatalog.data['armors'] || {}).map { |k,_| [k, EquipmentCatalog.armor_row(k)] }]
    else
      EquipmentRules::ARMOR_TABLE  rescue nil
    end

    if t && t[idx]
      row = t[idx]
      props = []
      props << 'ammunition' if row[:type] == 'ranged' && !row[:thrown]
      props << 'finesse'    if row[:finesse]
      props << 'heavy'      if row[:heavy]
      props << 'light'      if row[:light]
      props << 'loading'    if row[:loading]
      props << 'reach'      if row[:reach]
      props << 'special'    if row[:special]
      props << 'thrown'     if row[:thrown]
      props << 'two-handed' if row[:hands].to_i == 2 && !row[:versatile]
      props << 'versatile'  if row[:versatile]

      return {
        index: idx,
        name: idx.tr('-', ' '),
        equipment_category: { index: 'weapon', name: 'Weapon' },
        weapon_category: row[:category].to_s,
        weapon_range: row[:type] == 'ranged' ? 'Ranged' : 'Melee',
        damage: row[:damage_die].to_s.empty? ? nil : { damage_dice: row[:damage_die] },
        two_handed_damage: row[:versatile_die] ? { damage_dice: row[:versatile_die] } : nil,
        range: row[:range] ? { normal: row[:range].split('/').first.to_i, long: row[:range].split('/').last.to_i } : nil,
        properties: props.map { |p| { index: p, name: weapon_property_name(p), url: "/api/v1/public/weapon_properties/#{p}" } }.compact,
        cost: (row[:cost_cp] ? cp_to_cost_hash(row[:cost_cp]) : nil),
        weight: row[:weight_kg],
        url: "/api/v1/public/equipment/#{idx}"
      }.compact
    end

    if a && a[idx]
      row = a[idx]
      name = idx.tr('-', ' ')
      ac = { base: row[:base], dex_bonus: !row[:dex_cap].to_i.zero?, max_bonus: row[:dex_cap] }
      return {
        index: idx,
        name: name,
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: row[:cat].capitalize,
        armor_class: ac,
        str_minimum: row[:str_req],
        stealth_disadvantage: !!row[:stealth_dis],
        cost: (row[:cost_cp] ? cp_to_cost_hash(row[:cost_cp]) : nil),
        weight: row[:weight_kg],
        url: "/api/v1/public/equipment/#{idx}"
      }.compact
    end

    # Shields (heuristic)
    shields = if defined?(EquipmentCatalog) then EquipmentCatalog.shield_indexes else ['shield'] end
    if shields.any? { |s| idx.include?(s) }
      return {
        index: idx,
        name: idx.tr('-', ' '),
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: 'Shield',
        armor_class: { base: 2, dex_bonus: false },
        stealth_disadvantage: false,
        cost: nil,
        weight: nil,
        url: "/api/v1/public/equipment/#{idx}"
      }
    end

    nil
  end

  # Local equipment category list from EquipmentRules
  def local_equipment_category(idx)
    return nil unless defined?(EquipmentRules)
    t = if defined?(EquipmentCatalog) && EquipmentCatalog.data['weapons'].present?
      EquipmentCatalog.data['weapons']
    else
      EquipmentRules::WEAPON_TABLE rescue nil
    end
    a = if defined?(EquipmentCatalog) && EquipmentCatalog.data['armors'].present?
      EquipmentCatalog.data['armors']
    else
      EquipmentRules::ARMOR_TABLE  rescue nil
    end
    return nil unless t || a

    items = []
    title = idx

    case idx
    when 'simple-weapons'
      title = 'Simple Weapons'
      items = if defined?(EquipmentCatalog) && t.is_a?(Hash) && t.values.first.is_a?(Hash) && t.values.first['category']
        t.select { |_k, v| v['category'] == 'simple' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'simple' }.map { |k, _| k }
      end
    when 'martial-weapons'
      title = 'Martial Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['category']
        t.select { |_k, v| v['category'] == 'martial' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'martial' }.map { |k, _| k }
      end
    when 'simple-melee-weapons'
      title = 'Simple Melee Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'simple' && v['type'] == 'melee' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'simple' && v[:type] == 'melee' }.map { |k, _| k }
      end
    when 'simple-ranged-weapons'
      title = 'Simple Ranged Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'simple' && v['type'] == 'ranged' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'simple' && v[:type] == 'ranged' }.map { |k, _| k }
      end
    when 'martial-melee-weapons'
      title = 'Martial Melee Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'martial' && v['type'] == 'melee' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'martial' && v[:type] == 'melee' }.map { |k, _| k }
      end
    when 'martial-ranged-weapons'
      title = 'Martial Ranged Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'martial' && v['type'] == 'ranged' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'martial' && v[:type] == 'ranged' }.map { |k, _| k }
      end
    when 'armor'
      title = 'Armor'
      items = a.keys + (defined?(EquipmentCatalog) ? EquipmentCatalog.shield_indexes : ['shield'])
    when 'shields'
      title = 'Shields'
      items = (defined?(EquipmentCatalog) ? EquipmentCatalog.shield_indexes : ['shield'])
    else
      return nil
    end

    {
      index: idx,
      name: title,
      equipment: items.map { |k| { index: k, name: k.tr('-', ' '), url: "/api/v1/public/equipment/#{k}" } }
    }
  end
end
