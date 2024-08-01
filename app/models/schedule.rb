class Schedule < ApplicationRecord
  enum status: { reserved: 0, waiting: 1 }

  belongs_to :date_dimension

  validates :status, :date_dimension_id, :group_id, :title, presence: true
end