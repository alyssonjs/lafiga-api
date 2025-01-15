class Klass < ApplicationRecord
  validates :name, presence: true
  
  has_many :sub_klasses
end