class SubKlassLevel < ApplicationRecord
  belongs_to :sub_klass
  has_and_belongs_to_many :features

  validates :level, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 20 }
end

