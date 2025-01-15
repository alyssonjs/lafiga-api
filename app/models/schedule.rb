class Schedule < ApplicationRecord
  enum status: { reserved: 0, waiting: 1 }

  belongs_to :date_dimension
  belongs_to :group

  validates :status, :date_dimension_id, :title, presence: true
  before_save :check_date_availability

  private

  def check_date_availability
    if !date_dimension.available
      errors.add(:base, "A data selecionada não está disponível.")
      throw(:abort)
    end
  end
end
