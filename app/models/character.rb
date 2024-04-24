class Character < ApplicationRecord

  validates :name,:background, presence: true
  
  belongs_to :user
end
