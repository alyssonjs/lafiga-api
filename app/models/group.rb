class Group < ApplicationRecord
  enum season: { verao: 0, inverno: 1, primavera: 2, outono: 3 }

  validates :name, presence: true
  validates :day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }
end
