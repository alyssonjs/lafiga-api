class ScheduleCharacter < ApplicationRecord
  enum status: { confirmed: 0, pending: 1 }

  belongs_to :schedule
  belongs_to :character
end
