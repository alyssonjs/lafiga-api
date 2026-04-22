class Race < ApplicationRecord
  validates :name, presence: true
  validates :api_index, uniqueness: true, allow_nil: true

  has_many :sub_races, dependent: :destroy
  has_many :race_traits, dependent: :destroy
  has_many :traits, through: :race_traits

  # Traits where sub_race_id is NULL only (shared by all subraces of this race).
  # `traits` includes every subrace's rows via race_id alone — do not use for sheet summary.
  has_many :base_race_traits, -> { where(sub_race_id: nil) }, class_name: 'RaceTrait'
  has_many :base_traits, through: :base_race_traits, source: :trait
end
