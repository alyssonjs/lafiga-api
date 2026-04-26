# frozen_string_literal: true

# Catálogo canónico alinhado ao front (magicItemKindsMeta) e ao `config/magic_items.yml`.
# Normaliza raridade e categoria para a API, filtros do compêndio, bolsa e `MagicItemRules`.
module MagicItemCatalog
  RARITIES = %w[common uncommon rare very-rare legendary artifact].freeze

  CATEGORIES = [
    'weapon', 'ammunition', 'armor', 'shield', 'ring', 'wand', 'rod', 'staff',
    'gear', 'tool', 'potion', 'scroll',
    'vehicle', 'mount', 'kit',
  ].freeze

  # Rótulos PT (minúsculo) => valor persistido
  LABEL_TO_CATEGORY = {
    'arma' => 'weapon',
    'municao' => 'ammunition',
    'munição' => 'ammunition',
    'armadura' => 'armor',
    'escudo' => 'shield',
    'anel' => 'ring',
    'varinha' => 'wand',
    'bastao' => 'rod',
    'cajado' => 'staff',
    'equipamento' => 'gear',
    'ferramenta' => 'tool',
    'pocao' => 'potion',
    'poção' => 'potion',
    'pergaminho' => 'scroll',
    'veiculo' => 'vehicle',
    'veículo' => 'vehicle',
    'montaria' => 'mount',
    'kit' => 'kit',
  }.freeze

  MAGIC_TAG = 'magico'

  class << self
    # @return [String, nil] membro de RARITIES ou nil
    def normalize_rarity(raw)
      return nil if raw.blank?
      s = raw.to_s.strip.downcase
      s = s.tr('_', ' ').gsub(/-+/, ' ').gsub(/\s+/, ' ')
      compact = s.split(/\s+/).join('-')
      return compact if RARITIES.include?(compact)
      return s if RARITIES.include?(s)
      nil
    end

    # @return [String, nil] membro de CATEGORIES ou nil
    # Legado `wondrous item` mapeia para `gear` (a flag fica em `is_wondrous`).
    def normalize_category(raw)
      return nil if raw.blank?
      t = raw.to_s.strip
      s = t.downcase.tr('_', ' ').gsub(/-+/, ' ').gsub(/\s+/, ' ').strip
      return 'gear' if s == 'wondrous item' || s == 'wondrousitem' || s == 'wondrous'
      return 'gear' if s.start_with?('wondrous ')
      return s if CATEGORIES.include?(s)
      mapped = LABEL_TO_CATEGORY[s]
      return mapped if mapped
      s_hyphen = s.split(/\s+/).join('-')
      return 'gear' if s_hyphen == 'wondrous-item' || s_hyphen == 'wonderous-item' # typo
      nil
    end

    def ensure_magico_tag(tags)
      arr = Array(tags).compact.map { |x| x.to_s.strip }.reject(&:blank?).uniq
      return [MAGIC_TAG] if arr.empty?
      arr.include?(MAGIC_TAG) ? arr : (arr + [MAGIC_TAG])
    end
  end
end
