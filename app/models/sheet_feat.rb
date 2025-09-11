class SheetFeat < ApplicationRecord
  belongs_to :sheet
  belongs_to :feat

  validates :level_gained, presence: true, numericality: { greater_than: 0 }
  validates :sheet_id, uniqueness: { scope: :feat_id }

  # Parse choices JSON
  def choices_data
    return {} if choices.blank?
    JSON.parse(choices)
  rescue JSON::ParserError
    {}
  end

  # Get ability bonuses for this specific feat instance
  def ability_bonuses
    feat.get_ability_bonuses(choices_data)
  end

  # Get proficiency bonuses for this specific feat instance
  def proficiency_bonuses
    feat.get_proficiency_bonuses(choices_data)
  end
end
