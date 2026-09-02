# Resolvedor centralizado de Item para SheetItem.
#
# Por que existe:
#   Antes desse service, o controller `POST /api/v1/player/sheet_items` salvava
#   o SheetItem apenas com `item_name` (string crua), sem nunca ligar ao
#   catalogo Item via `item_id`. Resultado: 803 SheetItems no banco com
#   `item_id IS NULL`, sem regra de combate (peso, dano, custo, props),
#   duplicados ("Adaga", "adaga", "Adaga +1") e impossiveis de cruzar com a
#   pagina `/items` da Compendium.
#
#   O importer P81 (`provision-imported-as-bob.ts`) faz POSTs com nomes vindos
#   do excel ("Adaga", "Couro", "CD de magia", "Anel de Sinete"). Esse service
#   normaliza esses nomes em 4 etapas:
#     1. tenta achar Item ja existente por api_index/name (case/accents-agnostic)
#     2. tenta achar via EquipmentRules::WEAPON_TABLE (69 armas pre-mapeadas)
#     3. tenta achar via EquipmentRules::ARMOR_TABLE (12 armaduras)
#     4. cria um Item com kind inferido (gear default; weapon/armor/shield se
#        a tabela bater) e devolve o registro novo
#
# Convencao:
#   - api_index = slug ASCII em minusculo, ex.: "adaga", "couro", "anel-de-sinete"
#   - kind: 'weapon' | 'armor' | 'shield' | 'ammunition' | 'gear' | 'tool' | 'book' | 'consumable' | 'magic_item'
#   - cria com `find_or_create_by!(api_index:)` para garantir idempotencia
#
# Uso:
#   ItemResolver.new.resolve(name: "Adaga", category: "Armas")
#     # => Item(api_index="adaga", name="Adaga", kind="weapon")
#   ItemResolver.new.resolve(name: "Couro", category: "Armaduras & Escudos")
#     # => Item(api_index="couro", name="Couro", kind="armor")
#   ItemResolver.new.resolve(name: "Anel de Sinete", category: nil)
#     # => Item(api_index="anel-de-sinete", name="Anel de Sinete", kind="gear")
#
class ItemResolver
  # Slugs ambíguos criados por import/backfill sem categoria "Armas" (ex.: Excel
  # com só "Arco", ou typo "bestas leve") — viravam `kind: :gear` e poluíam o
  # catálogo público / busca na bolsa. Redirecionamos para o api_index de arma
  # canónico do equipment.yml antes de lookup_existing.
  AMBIGUOUS_WEAPON_SLUG_TO_CANON = {
    'arco' => 'arco-curto',
    'bestas-leve' => 'besta-leve',
    'bestas-leves' => 'besta-leve',
  }.freeze

  # Categorias usadas no SheetItem.category (vindas do importer e do background)
  WEAPON_CATEGORIES = ['Armas', 'weapon', 'weapons'].freeze
  ARMOR_CATEGORIES  = ['Armaduras & Escudos', 'armor', 'armors'].freeze

  # CABEÇALHOS de seção de ficha que o Excel manda como se fossem itens.
  #
  # ⚠️ Medido em prod: "CD de magia" virou Item e está em 14 fichas; "Armas",
  # em 15. Não são coisas — são títulos de coluna. Criá-los polui o catálogo e
  # a bolsa de todo mundo que importou. Devolver nil aqui deixa a linha da
  # ficha SEM vínculo (o fallback por nome do front ainda a mostra), que é
  # infinitamente melhor que um item-fantasma compartilhado por 14 personagens.
  SECTION_HEADER_SLUGS = %w[
    armas armaduras armaduras-escudos armadura equipamento equipamentos
    inventario vestuario acessorios
    cd-de-magia cd-de-habilidade cd-do-chi cd-de-conjuracao
  ].freeze

  # Acessórios "wearing" do excel (chegam sem categoria): nome → peça de
  # vestuário. A peça carrega a CATEGORIA do catálogo e o EQUIP_SLOT — o item
  # criado pelo import já nasce DECLARADO, como se tivesse saído do editor.
  #
  # ⚠️ Esta constante existia desde o início e NUNCA foi usada — os acessórios
  # do import caíam em `gear` pelado e dependiam da regex de nome do front, a
  # família de bugs que o sistema declarado (02/09) veio matar.
  ACCESSORY_KEYWORDS = {
    'amulet'   => ['amuleto', 'colar', 'gargantilha', 'medalhao', 'relicario', 'talisma'],
    'ring'     => ['anel'],
    'cloak'    => ['manto', 'capa', 'capote', 'broche'],
    'boots'    => ['botas', 'sapato', 'tornozeleira'],
    'helmet'   => ['elmo', 'capacete', 'tiara', 'diadema', 'chapeu'],
    'gloves'   => ['luvas', 'manopla'],
    'belt'     => ['cinto', 'cinturao'],
    'belt_leg' => ['cinto de perna', 'cinto da perna', 'coldre'],
    'mask'     => ['mascara', 'oculos'],
    'earrings' => ['brinco'],
    'bracelet_left' => ['bracelete', 'pulseira'],
  }.freeze

  # Peça → slot de equipagem (espelho do PIECE_TO_SLOT do front).
  ACCESSORY_PIECE_TO_SLOT = {
    'amulet' => 'amulet', 'ring' => 'ring_left', 'cloak' => 'cloak',
    'boots' => 'boots', 'helmet' => 'helmet', 'gloves' => 'gloves',
    'belt' => 'belt', 'belt_leg' => 'belt_leg_left', 'mask' => 'face',
    'earrings' => 'earrings', 'bracelet_left' => 'bracelet_left',
  }.freeze

  # Peça de acessório para este nome, ou nil. ⚠️ 'belt_leg' testa ANTES de
  # 'belt': "Cinto de perna" contém "cinto" — a mesma pegadinha que o dry-run
  # do backfill pegou.
  def accessory_piece_for(name)
    nm = ActiveSupport::Inflector.transliterate(name.to_s).downcase
    return 'belt_leg' if ACCESSORY_KEYWORDS['belt_leg'].any? { |k| nm.include?(k) }

    ACCESSORY_KEYWORDS.each do |piece, keywords|
      next if piece == 'belt_leg'
      return piece if keywords.any? { |k| nm.include?(k) }
    end
    nil
  end

  def initialize
    @cache_by_api_index = {}
    @cache_by_name_low  = {}
  end

  # Resolve um Item a partir do nome + categoria opcional.
  # Sempre devolve um Item persistido (cria se nao existir) ou nil quando o
  # nome e in-utilizavel (vazio, puramente numerico).
  def resolve(name:, category: nil)
    nm = name.to_s.strip
    return nil if nm.blank? || nm =~ /\A\d+(\.\d+)?\z/

    slug0 = slugify(nm)
    return nil if SECTION_HEADER_SLUGS.include?(slug0)
    if (canon_index = AMBIGUOUS_WEAPON_SLUG_TO_CANON[slug0])
      canon_item = Item.find_by(api_index: canon_index)
      return canon_item if canon_item

      row = EquipmentCatalog.data['weapons']&.dig(canon_index)
      label = row.is_a?(Hash) ? row['name'].to_s.strip.presence : nil
      return resolve(name: label, category: 'Armas') if label.present?
    end

    # 1. Existing Item match
    item = lookup_existing(nm)
    return item if item

    # 2/3. Match via EquipmentRules tables (mapeia para api_index canonico)
    canonical_slug, inferred_kind = canonical_from_rules(nm, category)
    if canonical_slug
      item = Item.find_by(api_index: canonical_slug)
      return item if item
      return create_item!(api_index: canonical_slug, name: nm, kind: inferred_kind || infer_kind(nm, category))
    end

    # 4. Fallback: cria Item novo a partir do nome + categoria
    create_item!(api_index: slugify(nm), name: nm, kind: infer_kind(nm, category))
  end

  # Slug ASCII para api_index. Publico pra reuso em rake/backfill.
  def slugify(s)
    ActiveSupport::Inflector
      .transliterate(s.to_s)
      .downcase
      .gsub(/[^a-z0-9]+/, '-')
      .gsub(/^-+|-+$/, '')
  end

  private

  def lookup_existing(name)
    # Tenta primeiro pelo slug ASCII, depois por LOWER(name). Cache por chamada.
    slug = slugify(name)
    if @cache_by_api_index.key?(slug)
      cached = @cache_by_api_index[slug]
      return cached if cached
    else
      found = Item.find_by(api_index: slug)
      @cache_by_api_index[slug] = found
      return found if found
    end

    key = name.to_s.downcase.strip
    return @cache_by_name_low[key] if @cache_by_name_low.key?(key)

    # Match por nome — case-insensitive, accent-stripped via slug round-trip
    candidate = Item.where('LOWER(name) = ?', key).first
    candidate ||= Item.find_each.detect { |i| slugify(i.name) == slug }
    @cache_by_name_low[key] = candidate
  end

  # Tenta mapear o nome para um api_index canonico via EquipmentRules.
  # Retorna [api_index, kind] ou [nil, nil] quando nao bate.
  #
  # WEAPON_TABLE/ARMOR_TABLE usam keys EN/PT (ex.: 'dagger' e 'adaga').
  # Quando bater em uma das duas, escolhemos o slug PT-BR como api_index
  # canonico (consistente com o resto do app que e PT-BR).
  PT_PREFERRED_SLUGS = {
    'dagger'        => 'adaga',
    'club'          => 'clava',
    'mace'          => 'maca',
    'sickle'        => 'foice',
    'spear'         => 'lanca',
    'quarterstaff'  => 'cajado',
    'handaxe'       => 'machadinha',
    'javelin'       => 'azagaia',
    'light-hammer'  => 'martelo-leve',
    'light-crossbow'=> 'besta-leve',
    'dart'          => 'dardo',
    'shortbow'      => 'arco-curto',
    'sling'         => 'funda',
    'battleaxe'     => 'machado-de-batalha',
    'glaive'        => 'glaive',
    'halberd'       => 'alabarda',
    'greataxe'      => 'machado-grande',
    'greatsword'    => 'montante',
    'maul'          => 'maul',
    'lance'         => 'lanca-de-cavalaria',
    'longsword'     => 'espada-longa',
    'morningstar'   => 'maca-estrela',
    'pike'          => 'pique',
    'rapier'        => 'rapieira',
    'scimitar'      => 'cimitarra',
    'shortsword'    => 'espada-curta',
    'trident'       => 'tridente',
    'warhammer'     => 'martelo-de-guerra',
    'whip'          => 'chicote',
    'blowgun'       => 'zarabatana',
    'hand-crossbow' => 'besta-de-mao',
    'heavy-crossbow'=> 'besta-pesada',
    'longbow'       => 'arco-longo',
    'net'           => 'rede',
  }.freeze

  # Nome de armadura (PT ou EN, em qualquer grafia) → `api_index` CANÔNICO.
  #
  # ⚠️ Este mapa apontava para slugs em PORTUGUÊS (`half-plate` => `meia-armadura`)
  # que NÃO são a convenção do catálogo — as 12 armaduras vivem com slug em
  # INGLÊS. Resultado: `create_item!` não achava a armadura de verdade e criava
  # uma CASCA VAZIA com o slug PT, sem `ac_base`/`dex_cap`. Quem vestisse essa
  # casca ficava sem CA de armadura (caía no 10+DES). Medido: 2 cascas
  # (`meia-armadura`, `cota-de-aneis`), 1 ficha cada.
  #
  # Agora todas as grafias — EN, PT do PHB e as variantes que a base tinha —
  # levam ao MESMO slug canônico. Escritor único, leitor tolerante.
  ARMOR_PT_SLUGS = {
    # inglês (identidade: já é o canônico)
    'padded' => 'padded', 'leather' => 'leather', 'studded-leather' => 'studded-leather',
    'hide' => 'hide', 'chain-shirt' => 'chain-shirt', 'scale-mail' => 'scale-mail',
    'breastplate' => 'breastplate', 'half-plate' => 'half-plate', 'ring-mail' => 'ring-mail',
    'chain-mail' => 'chain-mail', 'splint' => 'splint', 'plate' => 'plate',
    # português do PHB
    'acolchoada' => 'padded', 'couro' => 'leather', 'couro-batido' => 'studded-leather',
    'peles' => 'hide', 'camisao-de-malha' => 'chain-shirt', 'brunea' => 'scale-mail',
    'peitoral' => 'breastplate', 'meia-armadura' => 'half-plate',
    'cota-de-aneis' => 'ring-mail', 'cota-de-malha' => 'chain-mail',
    'cota-de-talas' => 'splint', 'armadura-de-placas' => 'plate',
    # variantes que a base já tinha gravadas (não podem virar item novo)
    'couro-reforcado' => 'studded-leather', 'armadura-couro-reforcado' => 'studded-leather',
    'gibao-de-peles' => 'hide', 'camisa-de-malha' => 'chain-shirt',
    'cota-de-escamas' => 'scale-mail', 'meia-armadura-de-placas' => 'half-plate',
    'malha-anelar' => 'ring-mail', 'lamelar' => 'splint',
    'placas-segmentadas' => 'splint', 'placa' => 'plate', 'placas' => 'plate',
  }.freeze

  def canonical_from_rules(name, _category)
    return [nil, nil] unless defined?(EquipmentRules)

    slug = slugify(name)
    en_slug = en_slug_for(slug)

    if EquipmentRules::WEAPON_TABLE.key?(slug) || EquipmentRules::WEAPON_TABLE.key?(en_slug)
      canonical = PT_PREFERRED_SLUGS[en_slug] || (EquipmentRules::WEAPON_TABLE.key?(slug) ? slug : en_slug)
      return [canonical, 'weapon']
    end

    # ⚠️ A condição olha o MAPA primeiro, não só a `ARMOR_TABLE`: aquela tabela
    # só tem chaves em INGLÊS, então um nome em português ("Meia-Armadura")
    # nunca entrava aqui e caía no `create_item!` com o slug PT — era assim que
    # nasciam as cascas sem `ac_base`. O mapa conhece as duas línguas.
    armadura = ARMOR_PT_SLUGS[en_slug] || ARMOR_PT_SLUGS[slug]
    if armadura || EquipmentRules::ARMOR_TABLE.key?(en_slug) || EquipmentRules::ARMOR_TABLE.key?(slug)
      return [armadura || slug, 'armor']
    end

    # Escudo: nome em PT-BR padrao
    if slug == 'escudo' || slug == 'shield'
      return ['escudo', 'shield']
    end

    [nil, nil]
  end

  # Mapeia variantes PT->EN para alcancar a WEAPON_TABLE quando o usuario
  # digitou o nome em portugues (que tambem esta na tabela em alguns casos).
  PT_TO_EN_FALLBACK = {
    'rapieira'           => 'rapier',
    'escimitarra'        => 'scimitar',
    'cimitarra'          => 'scimitar',
    'maca'               => 'mace',
    'maca-estrela'       => 'morningstar',
    'foice-curta'        => 'sickle',
    'claive'             => 'glaive', # typo comum no excel ("Claive" -> Glaive)
    'lanca'              => 'spear',
  }.freeze

  def en_slug_for(slug)
    PT_TO_EN_FALLBACK[slug] || slug
  end

  def infer_kind(name, category)
    cat = category.to_s.strip
    nm0 = ActiveSupport::Inflector.transliterate(name.to_s).downcase
    # ⚠️ ROUPA nunca é armadura, mesmo vinda da coluna "Armaduras & Escudos" da
    # ficha — foi assim que "Roupas"/"Roupa C." nasceram `kind: armor` sem CA
    # nenhuma. Roupa comum é gear (CA 10 + DES, sem item).
    return 'gear' if nm0.match?(/\broupas?\b|\bvestes?\b|\btraje\b/)

    return 'weapon' if WEAPON_CATEGORIES.any? { |c| c.casecmp?(cat) }
    return 'armor'  if ARMOR_CATEGORIES.any?  { |c| c.casecmp?(cat) }

    # Heuristica accent-agnostic: transliteramos antes de comparar pra que
    # "Ração", "Pocao", "Racão" etc. todos batam com 'racao'.
    nm = ActiveSupport::Inflector.transliterate(name.to_s).downcase
    return 'shield'      if nm.include?('escudo') || nm.include?('shield')
    return 'consumable'  if %w[pocao racao agua cantil tocha vela vinho cerveja].any? { |k| nm.include?(k) }
    return 'tool'        if %w[ferramenta kit instrumento].any? { |k| nm.include?(k) }
    return 'book'        if nm.include?('livro') || nm.include?('grimorio')
    return 'magic_item'  if nm.match?(/\s\+\d/)
    'gear'
  end

  # Cria o registro JÁ DECLARADO: o item que nasce do import carimba
  # `equip_slot` (e a peça, quando acessório) como se tivesse saído do editor.
  # Antes nascia só com nome+kind — a casca vazia que dependia da regex de
  # nome do front e virou o Coldre-de-coxa-inequipável, a armadura-sem-CA, etc.
  #
  # `source: 'import-auto'` deixa auditável o que o import inventou: é a
  # pergunta que os rakes de conserto fazem primeiro.
  def create_item!(api_index:, name:, kind:)
    piece = kind == 'gear' ? accessory_piece_for(name) : nil
    props = {}
    case kind
    when 'weapon' then props['equip_slot'] = 'main_hand'
    when 'armor'  then props['equip_slot'] = 'armor'
    when 'book'   then props['equip_slot'] = 'main_hand'
    when 'shield'
      props['equip_slot'] = 'shield'
      props['ac_bonus'] = 2 # PHB: todo escudo dá +2
    when 'gear'
      props['equip_slot'] = ACCESSORY_PIECE_TO_SLOT[piece] if piece
    end

    Item.find_or_create_by!(api_index: api_index) do |i|
      i.name = name
      i.kind = kind
      i.category = piece if piece
      i.props = props if props.any?
      i.source = 'import-auto'
    end
  rescue ActiveRecord::RecordNotUnique
    Item.find_by(api_index: api_index)
  end
end
