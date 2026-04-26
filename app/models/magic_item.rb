class MagicItem < ApplicationRecord
  before_validation :ensure_slug
  before_validation :normalize_catalog_fields
  before_save :ensure_magico_in_tags

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :rarity, inclusion: { in: MagicItemCatalog::RARITIES }, allow_nil: true, allow_blank: true
  validates :category, inclusion: { in: MagicItemCatalog::CATEGORIES }, allow_nil: true, allow_blank: true

  scope :by_rarity, ->(r) { where(rarity: r) if r.present? }
  scope :by_category, ->(c) { where(category: c) if c.present? }
  scope :attuned, ->(v = true) { where(requires_attunement: ActiveModel::Type::Boolean.new.cast(v)) }
  scope :search, ->(q) {
    if q.present?
      term = "%#{I18n.transliterate(q.to_s.downcase)}%"
      where('lower(name) LIKE ? OR lower(slug) LIKE ?', term, term)
    end
  }

  def as_json(options = nil)
    h = super(options)
    h = h.stringify_keys
    h['is_magical'] = true
    h['tags'] = MagicItemCatalog.ensure_magico_tag(self[:tags])
    h
  end

  def ensure_slug
    self.slug = parameterize(name) if slug.blank? && name.present?
  end

  def parameterize(text)
    I18n.transliterate(text.to_s).downcase.strip.gsub(/[^a-z0-9\-\s]/, '').gsub(/\s+/, '-').gsub(/-+/, '-')
  end

  private

  def normalize_catalog_fields
    r_in = self[:rarity]
    c_in = self[:category]
    if r_in.to_s.strip.present?
      n = MagicItemCatalog.normalize_rarity(r_in)
      if n.nil?
        errors.add(:rarity, 'não pôde ser mapeada para uma raridade canónica')
        self.rarity = nil
      else
        self.rarity = n
      end
    else
      self.rarity = nil
    end

    if c_in.to_s.strip.present?
      was_legacy_wondrous = MagicItemCategoryMigration.legacy_wondrous_value?(c_in)
      n = MagicItemCatalog.normalize_category(c_in)
      if n.nil?
        errors.add(:category, 'não pôde ser mapeada para uma categoria canónica')
        self.category = nil
      else
        self.category = n
      end
      self.is_wondrous = true if was_legacy_wondrous
    else
      self.category = nil
    end

    if has_attribute?(:is_wondrous)
      self.is_wondrous = ActiveModel::Type::Boolean.new.cast(self.is_wondrous)
    end
    self.requires_attunement = ActiveModel::Type::Boolean.new.cast(self.requires_attunement)
  end

  def ensure_magico_in_tags
    self.tags = MagicItemCatalog.ensure_magico_tag(self.tags)
  end
end
