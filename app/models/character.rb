class Character < ApplicationRecord

  validates :name,:background, presence: true
  
  belongs_to :user
  belongs_to :group, optional: true
  
  has_one :sheet
  has_one :schedule_character
end
