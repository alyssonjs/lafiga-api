class Klass < ApplicationRecord
  validates :name, presence: true
  
  has_many :sub_klasses
  has_many :sheets, through: :sheet_klasses
end