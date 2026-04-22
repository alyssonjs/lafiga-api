class Monster < ApplicationRecord
  # Catalogo de monstros (SRD + homebrew). Espelha o shape `MonsterEntry` do
  # front (`front-lafiga/src/app/data/monsterDatabase.ts`); a fonte rica fica
  # em `payload` JSONB e as colunas planas existem so para filtros/index.
  #
  # Padrao de leitura:
  #   `to_payload` devolve o objeto completo (camelCase no nivel certo) que o
  #   front consome direto em `MonsterContext` / `MONSTER_DATABASE` legacy.

  SOURCES = %w[srd homebrew].freeze

  before_validation :ensure_slug
  before_validation :sync_columns_from_payload

  validates :name,   presence: true
  validates :slug,   presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }

  scope :by_type,    ->(t) { where(monster_type: t) if t.present? }
  scope :by_source,  ->(s) { where(source: s) if s.present? }
  scope :by_cr_min,  ->(v) { where('cr_numeric >= ?', v.to_f) if v.present? }
  scope :by_cr_max,  ->(v) { where('cr_numeric <= ?', v.to_f) if v.present? }
  scope :search, ->(q) {
    if q.present?
      term = "%#{I18n.transliterate(q.to_s.downcase)}%"
      where(
        'lower(name) LIKE ? OR lower(name_en) LIKE ? OR lower(slug) LIKE ?',
        term, term, term
      )
    end
  }

  # Devolve o payload completo (mesmo shape do MonsterEntry no front),
  # mesclando colunas planas + payload JSONB. Sempre garante chave `id`
  # (alias do slug) para o front mapear sem ambiguidade.
  def to_payload
    base = (payload || {}).dup
    base['id']        = slug
    base['name']      = name
    base['nameEN']    = name_en if name_en.present?
    base['size']      ||= size
    base['type']      ||= monster_type
    base['alignment'] ||= alignment if alignment.present?
    base['ac']        ||= ac
    base['hp']        ||= hp
    base['cr']        ||= cr
    base['xp']        ||= xp
    base['source']    ||= source
    base
  end

  def self.cr_to_number(cr_value)
    return 0.0 if cr_value.nil?
    s = cr_value.to_s.strip
    case s
    when '1/8' then 0.125
    when '1/4' then 0.25
    when '1/2' then 0.5
    else
      s.to_f
    end
  end

  private

  def ensure_slug
    self.slug = parameterize(name) if slug.blank? && name.present?
  end

  # Sempre que o `payload` muda, ressincroniza as colunas planas para que
  # filtros do banco (cr_numeric, monster_type) reflitam o conteudo rico.
  # Se o payload tem o campo, ele eh autoritativo (sobrepoe defaults da
  # coluna); se nao tem, mantemos o valor explicito que o caller passou.
  def sync_columns_from_payload
    p = payload || {}
    self.size         = p['size']      if p['size'].present?
    self.monster_type = p['type']      if p['type'].present?
    self.alignment    = p['alignment'] if p['alignment'].present?
    self.cr           = p['cr'].to_s   if p['cr'].present?
    self.xp           = p['xp'].to_i   if p['xp'].present?
    self.ac           = p['ac'].to_i   if p['ac'].present?
    self.hp           = p['hp'].to_i   if p['hp'].present?
    self.name_en      = p['nameEN']    if p['nameEN'].present? && name_en.blank?
    self.cr_numeric   = self.class.cr_to_number(cr)
  end

  def parameterize(text)
    I18n.transliterate(text.to_s).downcase.strip.gsub(/[^a-z0-9\-\s]/, '').gsub(/\s+/, '-').gsub(/-+/, '-')
  end
end
