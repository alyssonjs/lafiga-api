class ScheduleCharacter < ApplicationRecord
  enum status: { confirmed: 0, pending: 1 }

  validates :character_id, uniqueness: true

  belongs_to :schedule
  belongs_to :character
end