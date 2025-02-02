class Race < ApplicationRecord
  validates :name, presence: true

  has_many :sub_races
end