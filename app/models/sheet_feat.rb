class SheetFeat < ApplicationRecord
  belongs_to :sheet
  belongs_to :feat

  validates :level_gained, presence: true, numericality: { greater_than: 0 }
  # Talentos repetíveis (PHB Adepto Elemental, Mágico Iniciante + houserule
  # Lafiga: Perito, Adepto Marcial, Poliglota, Conjurador de Ritual) podem
  # ter múltiplas linhas pra mesma sheet+feat, desde que em level_gained
  # distinto. A unique constraint do DB foi relaxada via migration
  # `20260513000000_allow_repeatable_feats_in_sheet_feats`. Aqui o validador
  # AR espelha a nova chave.
  validates :sheet_id, uniqueness: { scope: %i[feat_id level_gained] }

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
