class Api::V1::Public::EquipmentController < ApplicationController
  # `Item.category` que marca instrumento musical, em qualquer `kind`.
  INSTRUMENT_CATEGORY = 'instrument'

  # Transporte: veiculo terrestre, aquatico e arreios/selas. Mesmo carve-out do
  # `pack` e do `instrument` — vivem como `kind: gear` com categoria propria, o
  # que reusa o serializador de gear sem tocar no enum de `kind`.
  VEHICLE_CATEGORIES = %w[vehicle_land vehicle_water tack].freeze
  # Pocao mundana: `kind: consumable` + esta categoria. Sem ela, pocao, cantil e
  # tocha ficavam no mesmo balde e a aba Pocoes so via item magico.
  POTION_CATEGORY = 'potion'
  # Vocabulario de sub-tipo de consumivel. A aba Consumiveis serve TODOS os
  # `kind: consumable` e sub-categoriza por estes valores no front; `nil` cai em
  # "Outros". Poção continua com balde proprio (`:potions`) porque o "+ Novo
  # Item" da bolsa o consome separadamente.
  POISON_CATEGORY = 'poison'
  SUPPLY_CATEGORY = 'supply'
  ALCHEMICAL_CATEGORY = 'alchemical'
  # Pergaminho de magia: `kind: consumable` + esta categoria. Tinha aba propria
  # que vivia VAZIA (zero MagicItem `category: scroll`, zero `Item kind: scroll`)
  # enquanto os pergaminhos do mestre estavam como `gear` sem categoria. Gasta-se
  # ao conjurar, entao e consumivel — a magia vinculada vive em `props.spell_name`.
  SCROLL_CATEGORY = 'scroll'
  # Livro/tomo mundano. `kind: book` (a maioria) ou `gear` + esta categoria (o
  # Grimorio, que veio do seed do PHB).
  BOOK_CATEGORY = 'book'

  # Matéria-prima. `kind: material` com a família na `category` — um kind só
  # porque a família de um material é do MUNDO, não da natureza dele: o mesmo
  # minério vira liga na forja e reagente no encantamento. Trocar de category é
  # um UPDATE; trocar de kind seria migration.
  MATERIAL_KIND = 'material'
  # `poison-herb` é família própria DE PROPÓSITO: colhe-se com Kit de VENENO e
  # produz veneno, não remédio — distinção do mundo, não cosmética.
  MATERIAL_CATEGORIES = %w[
    essence monster-part herb poison-herb culinary ore alloy gem arcane
  ].freeze

  # Tesouro tem kind PRÓPRIO: obra de arte não é insumo de nada. A gema fica em
  # `material/gem` de propósito — essa SIM entra em receita (Gema Olho de Tigre
  # é ingrediente da Poção do Acerto Crítico).
  TREASURE_KIND = 'treasure'

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

  # GET /api/v1/public/equipment_catalog_snapshot
  # Uma ida ao servidor com todo o equipamento mundano (por categoria), para
  # evitar dezenas de round-trips no modal "Adicionar item" / buscas na bolsa.
  def equipment_catalog_snapshot
    # `instruments` precisa estar aqui: os baldes :gear/:tools EXCLUEM a
    # categoria, entao sem esta linha o instrumento sumiria do modal da bolsa.
    categories = %w[
      simple-weapons martial-weapons light-armor medium-armor heavy-armor shields
      gear packs tools instruments vehicles consumables potions books ammunition
    ]
    by_category = {}
    categories.each do |cat|
      rows = items_for_category_from_db(cat)
      next if rows.empty?

      by_category[cat] = rows.map { |it| build_equipment_from_item(it) }.compact
    end
    render json: { by_category: by_category }, status: :ok
  end

  private

  # Quem está pedindo é mestre? O catálogo é público (não tem `before_action` de
  # autenticação), mas o `apiClient` do front já manda `Authorization` quando há
  # sessão — dá para IDENTIFICAR sem passar a exigir login.
  #
  # Memoizado com `defined?` porque `false` é resposta válida: `||=` refaria a
  # leitura do token a cada item do catálogo (são centenas por requisição).
  def mestre_olhando?
    return @mestre_olhando if defined?(@mestre_olhando)

    usuario = ApiRequestAuth.call(request.headers).result
    @mestre_olhando = Group.user_is_dm?(usuario)
  rescue StandardError
    # Token podre não pode derrubar o catálogo inteiro — no máximo, esconde.
    @mestre_olhando = false
  end

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
    # Pacotes vivem como `kind: :gear` + `category: pack` (enum Item nao tem `pack`).
    when :gear
      # ATENCAO: `where.not` gera `NOT IN`, que e NULL-unsafe — os 205 `gear` com
      # `category: nil` ja NAO apareciam aqui antes desta linha existir (bug
      # PRE-EXISTENTE do `pack`, mantido de proposito para nao mudar o que a aba
      # "Itens Gerais" mostra hoje). O instrumento tem categoria preenchida,
      # entao entra na exclusao sem depender disso.
      Item.where(kind: 'gear')
          .where.not(category: ['pack', INSTRUMENT_CATEGORY, BOOK_CATEGORY, *VEHICLE_CATEGORIES])
          .order(:api_index).to_a
    when :packs
      Item.where(kind: 'gear', category: 'pack').order(:api_index).to_a
    when :tools
      # `IS DISTINCT FROM` e obrigatorio aqui: `where.not` derrubaria os 18 de 20
      # `tool` com `category: nil` junto com o instrumento.
      Item.where(kind: 'tool')
          .where('items.category IS DISTINCT FROM ?', INSTRUMENT_CATEGORY)
          .order(:api_index).to_a
    # Instrumento musical eh FERRAMENTA no PHB (tabela FERRAMENTAS), entao a base
    # nova nasce `kind: tool` + `category: instrument`. O filtro aqui eh SO por
    # categoria, de proposito: instrumento ja catalogado como `gear` (ex.:
    # "Instrumento Musical") aparece na aba sem precisar de migration. Os baldes
    # :gear e :tools excluem a categoria para o item nao viver em duas abas —
    # mesma mecanica que :gear ja usa para `pack`.
    when :instruments
      Item.where(category: INSTRUMENT_CATEGORY).order(:api_index).to_a
    # Aba "Equipamentos" do compendio: os tres grupos numa lista so, agrupados
    # no front pela `gear_category`.
    when :vehicles
      Item.where(category: VEHICLE_CATEGORIES).order(:category, :api_index).to_a
    when :consumables
      # Serve TODOS os consumiveis, poção INCLUSIVE: a aba deixou de ser
      # "Poções" e passou a ser "Consumiveis", com a poção como sub-tipo. Antes
      # daqui a poção estava numa aba e cantil/tocha noutra.
      Item.where(kind: 'consumable').order(:api_index).to_a
    when :potions
      # Pocao MUNDANA. A magica vive em `MagicItem` com `category: potion` e a
      # aba mostra as duas juntas.
      Item.where(kind: 'consumable', category: POTION_CATEGORY).order(:api_index).to_a
    when :treasure
      Item.where(kind: TREASURE_KIND).order(:value_gp, :api_index).to_a
    when :materials
      Item.where(kind: MATERIAL_KIND).order(:category, :api_index).to_a
    when *MATERIAL_CATEGORIES.map { |c| :"material_#{c.tr('-', '_')}" }
      Item.where(kind: MATERIAL_KIND, category: key.to_s.sub('material_', '').tr('_', '-'))
          .order(:api_index).to_a
    when :books
      # Livro e tomo MUNDANOS. O `kind: book` existia no catalogo e NENHUM balde
      # o servia — 11 livros nao apareciam em aba nenhuma. O Grimorio e
      # `kind: gear` + `category: book`, entao entra pelos dois caminhos.
      Item.where(kind: 'book')
          .or(Item.where(kind: 'gear', category: BOOK_CATEGORY))
          .order(:api_index).to_a
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
    return :potions         if %w[potions pocoes].include?(s)
    return :books           if %w[books livros tomos].include?(s)
    return :gear            if %w[adventuring-gear gear equipamentos utilidades equipment-gear].include?(s)
    return :packs           if %w[equipment-packs packs mochilas].include?(s)
    return :instruments     if %w[instruments instrumentos musical-instruments].include?(s)
    return :vehicles        if %w[vehicles veiculos transportes mounts-and-vehicles].include?(s)
    return :tools           if %w[tools ferramentas instruments-misc].include?(s)
    return :consumables     if %w[consumables consumivel consumiveis].include?(s)
    return :treasure        if %w[treasure tesouros obras-de-arte art-objects].include?(s)
    return :materials       if %w[materials materias-primas materia-prima raw-materials].include?(s)
    # Sub-abas por família: `materials-essence`, `materials-gem`, ...
    if s.start_with?('materials-')
      fam = s.sub('materials-', '')
      return :"material_#{fam.tr('-', '_')}" if MATERIAL_CATEGORIES.include?(fam)
    end
    return :none            if s == 'none'
    nil
  end

  def contents_with_kind(raw)
    return raw unless raw.is_a?(Array)

    indices = raw.filter_map { |c| c.is_a?(Hash) ? (c['item_index'] || c[:item_index]) : nil }
    return raw if indices.empty?

    por_indice = Item.where(api_index: indices).index_by(&:api_index)
    raw.map do |c|
      next c unless c.is_a?(Hash)

      alvo = por_indice[c['item_index'] || c[:item_index]]
      next c unless alvo

      c.merge('kind' => alvo.kind, 'category' => alvo.category)
    end
  end

  def build_crafting_json(it)
    return nil unless defined?(CraftingRecipe)

    recipe = it.try(:crafting_recipe)
    return nil unless recipe

    {
      craft: recipe.craft,
      dc: recipe.dc,
      days: recipe.days&.to_f,
      cost: recipe.craft_cost_gp&.to_f,
      processes: Array(recipe.processes),
      scaling: recipe.scaling.presence,
      ingredients: recipe.ingredients.map do |ing|
        {
          # `item_index` é o LINK: nulo aqui significa magia ou texto livre,
          # e o front tem de mostrar assim mesmo — a Poção de Resistência
          # depende de um "Componente Extra" que não é item nenhum.
          item_index: ing.ingredient_item&.api_index,
          spell_name: ing.spell&.name,
          raw_text: ing.raw_text.presence,
          name: ing.display_name,
          quantity: ing.quantity&.to_f,
          unit: ing.unit,
          alternative_group: ing.alternative_group,
          is_choice: ing.is_choice,
        }.compact
      end,
    }.compact
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
      props = Array(wp['properties']).map { |v| v.to_s.downcase }
      props << 'ammunition' if wp['type'] == 'ranged' && !wp['thrown']
      %w[finesse light heavy loading reach special thrown versatile two-handed].each do |p|
        props << p if wp[p]
      end
      props << 'two-handed' if wp['hands'].to_i == 2 && !props.include?('versatile')
      props.uniq!
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      # `weight` do payload e em LB (convencao do livro, kg x 2): o compendio
      # rotula "lb" e a bolsa grava `weight_lb` — mandar kg cru sub-contava a
      # carga em ~2x. O banco continua canonico em kg.
      weight_lb = (defined?(EquipmentRules) ? EquipmentRules.item_weight_lb(it) : nil) rescue nil
      return {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: 'weapon', name: 'Weapon' },
        weapon_category: it.category.to_s,
        weapon_range: wp['type'] == 'ranged' ? 'Ranged' : 'Melee',
        damage: wp['damage_die'].to_s.empty? ? nil : { damage_dice: wp['damage_die'], damage_type: wp['damage_type'] },
        two_handed_damage: wp['versatile_die'] ? { damage_dice: wp['versatile_die'] } : nil,
        range: wp['range'] ? { normal: wp['range'].to_s.split('/').first.to_i, long: wp['range'].to_s.split('/').last.to_i } : nil,
        properties: props.map { |p| { index: p, name: weapon_property_name(p), url: "/api/v1/public/weapon_properties/#{p}" } },
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_lb,
        chibi_weapon_svg_id: wp['chibi_weapon_svg_id'],
        card_icon_id: wp['card_icon_id'],
        url: "/api/v1/public/equipment/#{it.api_index}"
      }.compact
    when 'armor'
      ap = it.props || {}
      ac = { base: ap['ac_base'], dex_bonus: !ap['dex_cap'].to_i.zero?, max_bonus: ap['dex_cap'] }
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      # `weight` do payload e em LB (convencao do livro, kg x 2): o compendio
      # rotula "lb" e a bolsa grava `weight_lb` — mandar kg cru sub-contava a
      # carga em ~2x. O banco continua canonico em kg.
      weight_lb = (defined?(EquipmentRules) ? EquipmentRules.item_weight_lb(it) : nil) rescue nil
      return {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: it.category.to_s.capitalize,
        armor_class: ac,
        str_minimum: ap['str_req'],
        stealth_disadvantage: !!ap['stealth_dis'],
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_lb,
        # Icone escolhido no editor. Sem serializar, o mestre escolhe e a
        # listagem nunca ve — mesma lacuna ja consertada em gear/tool.
        card_icon_id: ap['card_icon_id'].presence,
        url: "/api/v1/public/equipment/#{it.api_index}"
      }.compact
    when 'shield'
      sp = it.props || {}
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      # `weight` do payload e em LB (convencao do livro, kg x 2): o compendio
      # rotula "lb" e a bolsa grava `weight_lb` — mandar kg cru sub-contava a
      # carga em ~2x. O banco continua canonico em kg.
      weight_lb = (defined?(EquipmentRules) ? EquipmentRules.item_weight_lb(it) : nil) rescue nil
      return {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: 'Shield',
        # Escudo do PHB é +2, mas o mestre pode criar um com bônus próprio.
        armor_class: { base: sp['ac_base'].presence || 2, dex_bonus: false },
        stealth_disadvantage: false,
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_lb,
        card_icon_id: sp['card_icon_id'].presence,
        url: "/api/v1/public/equipment/#{it.api_index}"
      }
    when 'gear', 'pack', 'tool', 'consumable', 'book', 'magic_item', 'ammunition', 'material', 'treasure'
      cost_cp = (defined?(EquipmentRules) ? EquipmentRules.item_cost_cp(it) : nil) rescue nil
      # `weight` do payload e em LB (convencao do livro, kg x 2): o compendio
      # rotula "lb" e a bolsa grava `weight_lb` — mandar kg cru sub-contava a
      # carga em ~2x. O banco continua canonico em kg.
      weight_lb = (defined?(EquipmentRules) ? EquipmentRules.item_weight_lb(it) : nil) rescue nil
      props = it.props || {}
      # A categoria vence o kind aqui: instrumento existe como `tool` (novo) e
      # como `gear` (legado), e nos dois casos o rotulo tem que dizer o mesmo —
      # senao o modal da bolsa mostra "Adventuring Gear" para um alaude.
      category_index, category_name = if it.category.to_s == INSTRUMENT_CATEGORY
        ['instruments', 'Musical Instruments']
      elsif VEHICLE_CATEGORIES.include?(it.category.to_s)
        ['vehicles', 'Mounts and Vehicles']
      else
        case it.kind
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
      when 'material'
        ['materials', 'Matérias-Primas']
      when 'treasure'
        ['treasure', 'Obras de Arte']
      else
        # Pacotes importados como `kind: :gear` + `category: pack` (ver equipment:import_items).
        if it.kind == 'gear' && it.category.to_s == 'pack'
          ['equipment-packs', 'Equipment Pack']
        else
          ['adventuring-gear', 'Adventuring Gear']
        end
        end
      end
      {
        index: it.api_index,
        name: it.name,
        equipment_category: { index: category_index, name: category_name },
        gear_category: it.category,
        # Vestuário mundano: a peça vive em `category` (gear_category) e o slot
        # de equipar é escolhido pelo mestre — peças sem slot dedicado na ficha
        # (máscara, tomo, …) ficam sem `equip_slot`.
        equip_slot: props['equip_slot'].presence,
        # Visual escolhido pelo mestre no editor (mesmas chaves que a arma usa).
        # Sem isto o DM escolhe modelo/icone, eles gravam em props e a listagem
        # nunca os ve — o card cai no generico.
        card_icon_id: props['card_icon_id'].presence,
        chibi_weapon_svg_id: props['chibi_weapon_svg_id'].presence,
        # Magia do pergaminho. Guardada por NOME (nao por id): id da API e
        # numerico e nao sobrevive a um re-seed do catalogo de magias; o nome e
        # o que o resto da base ja usa (ex.: `sub_klasses.terrain_spells`).
        spell_name: props['spell_name'].presence,
        # Usos limitados (Kit de Primeiros Socorros: 10) e o token de recarga.
        # Sem serializar, o jogador so descobre que o kit tem dez usos DEPOIS de
        # comprar — o dado existe no catalogo e nao chegava a lugar nenhum.
        uses_max: props['uses_max'].presence&.to_i,
        uses_recharge: MagicItemCatalog.normalize_recharge(props['uses_recharge']),
        # Recipiente de municao: o que cabe e quanto. O servidor BLOQUEIA por
        # capacidade, entao esconder isto faz o aviso chegar so depois do erro.
        ammunition_types: props['ammunition_types'].presence,
        ammunition_capacity: props['ammunition_capacity'].presence&.to_i,
        stackable: props.key?('stackable') ? !!props['stackable'] : nil,
        # Matéria-prima se compra por MEDIDA, não por peça: o preço da essência é
        # por ml. Sem a unidade no payload, "0,5 po" de Extrato Vegetal parece o
        # preço do frasco inteiro em vez do mililitro.
        material_unit: props['unit'].presence,
        material_note: props['note'].presence,
        # Faixa do DMG (25/250/750/2500/7500 po): é por ela que o mestre sorteia
        # o saque, então precisa chegar ao filtro da aba.
        art_tier: props['art_tier'].presence,
        # Gema: tier e o poder místico são do MUNDO — o joalheiro descreve a
        # pedra ao vendê-la, então o jogador vê.
        gem_tier: props['gem_tier'].presence,
        gem_power: props['gem_power'].presence,
        # ⚠️ Os efeitos de ENCAIXE são do mestre. Esconder só no front deixaria
        # o texto viajando no payload — quem abrisse o devtools leria a mecânica
        # inteira. O corte é aqui: a chave nem existe para quem não é mestre.
        gem_weapon_effect: (props['gem_weapon_effect'].presence if mestre_olhando?),
        gem_apparel_effect: (props['gem_apparel_effect'].presence if mestre_olhando?),
        # Erva/venenosa: onde-quando-como COLHER e o que ela vira depois de
        # preparada. Sem serializar, o dado existe no catálogo e não chega à
        # ficha — a mesma classe de gap dos usos de kit.
        plant_type: props['plant_type'].presence,
        foraging: props['foraging'].presence,
        preparation: props['preparation'].presence,
        # Receita de fabricação. Vai no payload do PRODUTO (não do material):
        # é a ficha de "como fazer isto". Os ingredientes carregam o `index` do
        # item para o front poder navegar até ele — e para o NPC ferreiro exigir
        # o material da bolsa em vez de conferir por nome.
        crafting: build_crafting_json(it),
        # Transporte: o PHB dá velocidade em km/h no veiculo aquatico, e o custo
        # da armadura de montaria e um MULTIPLICADOR (x4), nao valor fixo —
        # serializar como custo normal mostraria "0 po", que e mentira.
        speed_kmh: props['speed_kmh'].presence,
        # Onde o item entra na montaria (sela/barda/alforje/freio) e quanto o
        # alforje carrega. Sem isto o front nao sabe montar os slots.
        mount_slot: props['mount_slot'].presence,
        capacity_lb: props['capacity_lb'].presence,
        barding_of: props['barding_of'].presence,
        cost_multiplier: props['cost_multiplier'].presence,
        service: props['service'] == true ? true : nil,
        cost: cost_cp ? cp_to_cost_hash(cost_cp) : nil,
        weight: weight_lb,
        description: it.description,
        # Conteúdo do pacote com `kind`/`category` de cada peça: sem isso o
        # front não sabe para QUAL aba mandar o clique (tocha é Consumíveis,
        # mochila é Equipamentos, flecha é Munições).
        contents: contents_with_kind(props['contents'] || props[:contents]),
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
