class MagicItem < ApplicationRecord
  before_validation :ensure_slug

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :by_rarity, ->(r) { where(rarity: r) if r.present? }
  scope :by_category, ->(c) { where(category: c) if c.present? }
  scope :attuned, ->(v = true) { where(requires_attunement: ActiveModel::Type::Boolean.new.cast(v)) }
  scope :search, ->(q) {
    if q.present?
      term = "%#{I18n.transliterate(q.to_s.downcase)}%"
      where('lower(name) LIKE ? OR lower(slug) LIKE ?', term, term)
    end
  }

  def ensure_slug
    self.slug = parameterize(name) if slug.blank? && name.present?
  end

  def parameterize(text)
    I18n.transliterate(text.to_s).downcase.strip.gsub(/[^a-z0-9\-\s]/,'').gsub(/\s+/,'-').gsub(/-+/,'-')
  end
end
