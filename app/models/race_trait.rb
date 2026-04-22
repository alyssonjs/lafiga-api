class RaceTrait < ApplicationRecord
  belongs_to :race
  belongs_to :trait
  belongs_to :sub_race, optional: true

  validates :trait_id, uniqueness: { scope: [:race_id, :sub_race_id] }
end
