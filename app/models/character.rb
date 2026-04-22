class Character < ApplicationRecord

  enum status: { draft: 0, active: 1 }

  validates :name, :background, presence: true, unless: :draft?
  
  belongs_to :user
  belongs_to :group, optional: true
  
  has_one :sheet
  has_one :character_dm_level_unlock, dependent: :destroy
  has_many :schedule_characters, dependent: :destroy
  has_many :schedules, through: :schedule_characters
  has_many :diary_entries, dependent: :destroy
  has_many :combat_combatants, as: :combatable, dependent: :destroy
end
