class SheetKnownSpell < ApplicationRecord
  self.table_name = 'sheet_known_spells'
  belongs_to :sheet_klass
  belongs_to :spell

  # Validações
  validates :source, inclusion: { in: %w[class race feat subclass background], allow_nil: true }
  validates :uses_per_rest, inclusion: { in: %w[LR SR], allow_nil: true }
  validates :uses_remaining, numericality: { greater_than_or_equal_to: 0 }, if: -> { uses_per_rest.present? }

  # Scopes úteis
  scope :from_race, -> { where(source: 'race') }
  scope :from_class, -> { where(source: 'class') }
  scope :from_feat, -> { where(source: 'feat') }
  scope :cantrips, -> { joins(:spell).where(spells: { level: 0 }) }
  scope :with_limited_uses, -> { where.not(uses_per_rest: nil) }

  # Métodos de helper
  def cantrip?
    spell&.level == 0
  end

  def has_uses?
    uses_per_rest.present?
  end

  def uses_exhausted?
    has_uses? && uses_remaining <= 0
  end

  def restore_uses!
    return unless has_uses?
    update(uses_remaining: calculate_max_uses)
  end

  def use_once!
    return false unless has_uses? && uses_remaining > 0
    decrement!(:uses_remaining)
    true
  end

  private

  def calculate_max_uses
    # Magias raciais geralmente são 1x por descanso
    # Pode ser expandido no futuro para casos especiais
    1
  end
end

