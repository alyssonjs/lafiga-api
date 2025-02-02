class Sheet < ApplicationRecord
  validates :character_id, uniqueness: true
  validate :sub_race_belongs_to_race

  belongs_to :character
  belongs_to :race
  belongs_to :sub_race, optional: true

  has_many :sheet_klasses
  has_many :klasses, through: :sheet_klasses

  private

  def sub_race_belongs_to_race
    if sub_race.present? && sub_race.race_id != race_id
      errors.add(:sub_race, "deve pertencer à raça selecionada.")
    end
  end
end
