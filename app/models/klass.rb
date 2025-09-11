class Klass < ApplicationRecord
  validates :name, presence: true
  
  has_many :sub_klasses
  has_many :class_levels, dependent: :destroy
  has_many :sheets, through: :sheet_klasses
  has_many :features, through: :class_levels
end
