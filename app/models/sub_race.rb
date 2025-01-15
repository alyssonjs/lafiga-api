class SubRace < ApplicationRecord
  validates :name, :race_id, presence: true

  belongs_to :race
end