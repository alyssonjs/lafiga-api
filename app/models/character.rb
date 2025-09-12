class Character < ApplicationRecord

  validates :name,:background, presence: true
  
  belongs_to :user
  belongs_to :group, optional: true
  
  has_one :sheet
  has_many :schedule_characters, dependent: :destroy
  has_many :schedules, through: :schedule_characters
end
