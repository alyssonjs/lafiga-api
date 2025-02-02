class SheetKlass < ApplicationRecord
  validates :level, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 20 }
  validate :sub_klass_belongs_to_klass

  belongs_to :sheet
  belongs_to :klass
  belongs_to :sub_klass, optional: true

  private

  def sub_klass_belongs_to_klass
    if sub_klass.present? && sub_klass.klass_id != klass_id
      errors.add(:sub_klass, "deve pertencer à classe selecionada.")
    end
  end
end