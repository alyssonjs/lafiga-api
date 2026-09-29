# frozen_string_literal: true

# Uma CRIAÇÃO do personagem: a receita, quantas unidades, e os dias de trabalho
# que o Mestre conta sessão a sessão.
#
# ⚠️ Os materiais NÃO saem ao iniciar — saem ao concluir (`Crafting::Complete`).
# Enquanto está em andamento, a criação só "compromete" materiais: é assim que
# duas criações não contam o mesmo frasco.
class SheetCraft < ApplicationRecord
  STATUSES = %w[in_progress done].freeze
  MAX_DAYS = 999_999 # teto do decimal(8,2)

  belongs_to :sheet
  belongs_to :crafting_recipe, optional: true

  validates :product_name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 999 }
  validates :days_required, numericality: { greater_than: 0, less_than_or_equal_to: MAX_DAYS }
  validates :days_worked, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_DAYS }

  scope :in_progress, -> { where(status: 'in_progress') }
  scope :done, -> { where(status: 'done') }

  def in_progress?
    status == 'in_progress'
  end

  def ready?
    days_worked >= days_required
  end
end
