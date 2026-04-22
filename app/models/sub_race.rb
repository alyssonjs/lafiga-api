class SubRace < ApplicationRecord
  validates :name, :race_id, presence: true
  validates :api_index, uniqueness: { scope: :race_id }, allow_nil: true

  belongs_to :race
  has_many :race_traits, dependent: :destroy
  has_many :traits, through: :race_traits
end
