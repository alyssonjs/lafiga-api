class SheetKlass < ApplicationRecord
  validates :level, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 20 }
  validate :sub_klass_belongs_to_klass
  validate :total_levels_cannot_exceed_20
  validate :subclass_only_after_threshold

  belongs_to :sheet
  belongs_to :klass
  belongs_to :sub_klass, optional: true

  private

  def sub_klass_belongs_to_klass
    if sub_klass.present? && sub_klass.klass_id != klass_id
      errors.add(:sub_klass, "deve pertencer à classe selecionada.")
    end
  end

  def total_levels_cannot_exceed_20
    return unless sheet && klass
    total = sheet.sheet_klasses.where.not(id: id).sum(:level).to_i + level.to_i
    errors.add(:level, 'soma dos níveis não pode exceder 20') if total > 20
  end

  def subclass_only_after_threshold
    return unless sub_klass.present? && klass
    threshold = klass.try(:subclass_level)
    return if threshold.blank?
    errors.add(:sub_klass, "só pode ser definida a partir do nível #{threshold}") if level.to_i < threshold.to_i
  end
end
