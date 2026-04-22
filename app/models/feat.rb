class Feat < ApplicationRecord
  has_many :sheet_feats, dependent: :destroy
  has_many :sheets, through: :sheet_feats

  validates :name, presence: true, uniqueness: true

  # Parse JSON fields
  def prerequisites_data
    return {} if prerequisites.blank?
    JSON.parse(prerequisites)
  rescue JSON::ParserError
    {}
  end

  def ability_bonuses_data
    return {} if ability_bonuses.blank?
    JSON.parse(ability_bonuses)
  rescue JSON::ParserError
    {}
  end

  def proficiency_bonuses_data
    return {} if proficiency_bonuses.blank?
    JSON.parse(proficiency_bonuses)
  rescue JSON::ParserError
    {}
  end

  def features_data
    raw = features
    return {} if raw.blank?
    data = raw
    if raw.is_a?(String)
      begin
        data = JSON.parse(raw)
      rescue JSON::ParserError
        begin
          data = JSON.parse(raw.to_s.gsub('=>', ':'))
        rescue StandardError
          return {}
        end
      end
    end
    return {} unless data.is_a?(Hash)
    out = data.transform_keys(&:to_s)
    if out.key?('description') && !out.key?('desc')
      out['desc'] = out.delete('description')
    end
    out
  end

  # Get ability score bonuses for a specific feat
  def get_ability_bonuses(choices = {})
    bonuses = ability_bonuses_data
    return bonuses if bonuses.blank?

    # Handle feats with choices (like Resilient)
    if bonuses['choose']
      chosen_ability = choices[:ability] || choices['ability']
      return { chosen_ability => bonuses['choose']['amount'] } if chosen_ability
    end

    bonuses
  end

  # Get proficiency bonuses for a specific feat
  def get_proficiency_bonuses(choices = {})
    prof_bonuses = proficiency_bonuses_data
    return prof_bonuses if prof_bonuses.blank?

    # Handle feats with choices
    if prof_bonuses['choose']
      chosen_proficiencies = choices[:proficiencies] || choices['proficiencies'] || []
      return { 'skills' => chosen_proficiencies } if chosen_proficiencies.any?
    end

    prof_bonuses
  end
end
