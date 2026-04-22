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
  # Categorias usadas no SheetItem.category (vindas do importer e do background)
  WEAPON_CATEGORIES = ['Armas', 'weapon', 'weapons'].freeze
  ARMOR_CATEGORIES  = ['Armaduras & Escudos', 'armor', 'armors'].freeze

  # Heuristicas para inferir kind a partir do nome quando categoria for nula
  # (acessorios "wearing" do excel chegam sem categoria).
  ACCESSORY_KEYWORDS = {
    'amulet'   => ['amuleto'],
    'ring'     => ['anel'],
    'cloak'    => ['manto', 'capa'],
    'boots'    => ['botas', 'sapato'],
    'helmet'   => ['elmo', 'capacete'],
    'gloves'   => ['luvas', 'manopla'],
    'belt'     => ['cinto', 'cinturao'],
  }.freeze

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

  ARMOR_PT_SLUGS = {
    'padded'           => 'acolchoada',
    'leather'          => 'couro',
    'studded-leather'  => 'couro-batido',
    'hide'             => 'peles',
    'chain-shirt'      => 'camisao-de-malha',
    'scale-mail'       => 'brunea',
    'breastplate'      => 'peitoral',
    'half-plate'       => 'meia-armadura',
    'ring-mail'        => 'cota-de-aneis',
    'chain-mail'       => 'cota-de-malha',
    'splint'           => 'lamelar',
    'plate'            => 'placa',
  }.freeze

  def canonical_from_rules(name, _category)
    return [nil, nil] unless defined?(EquipmentRules)

    slug = slugify(name)
    en_slug = en_slug_for(slug)

    if EquipmentRules::WEAPON_TABLE.key?(slug) || EquipmentRules::WEAPON_TABLE.key?(en_slug)
      canonical = PT_PREFERRED_SLUGS[en_slug] || (EquipmentRules::WEAPON_TABLE.key?(slug) ? slug : en_slug)
      return [canonical, 'weapon']
    end

    if EquipmentRules::ARMOR_TABLE.key?(en_slug) || EquipmentRules::ARMOR_TABLE.key?(slug)
      canonical = ARMOR_PT_SLUGS[en_slug] || ARMOR_PT_SLUGS[slug] || slug
      return [canonical, 'armor']
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

  def create_item!(api_index:, name:, kind:)
    Item.find_or_create_by!(api_index: api_index) do |i|
      i.name = name
      i.kind = kind
    end
  rescue ActiveRecord::RecordNotUnique
    Item.find_by(api_index: api_index)
  end
end
