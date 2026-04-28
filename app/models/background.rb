# frozen_string_literal: true

class Background < ApplicationRecord
  has_many :sheets, dependent: :restrict_with_exception

  validates :api_index, presence: true, uniqueness: true
  validates :name, presence: true
  validate :parent_not_self
  validate :parent_must_resolve_when_set

  before_validation :normalize_parent_api_index

  after_commit :invalidate_rules_cache

  scope :published, -> { where(published: true) }
  scope :variants, -> { where("parent_api_index IS NOT NULL AND parent_api_index <> ''") }
  scope :roots, -> { where(parent_api_index: [nil, '']) }

  # rules: JSONB — mesma forma canónica de BackgroundRules (skills, tools, languages,
  # equipment, feature, opcional personality_traits/ideals/bonds/flaws para o wizard).
  # Variações PHB/homebrew: parent_api_index aponta para o api_index do antecedente base;
  # rules guarda só overrides que fazem deep_merge no pai.

  private

  def normalize_parent_api_index
    self.parent_api_index = parent_api_index.presence
  end

  def parent_not_self
    return if parent_api_index.blank?

    errors.add(:parent_api_index, 'não pode ser o próprio antecedente') if parent_api_index == api_index
  end

  def parent_must_resolve_when_set
    return if parent_api_index.blank?

    errors.add(:parent_api_index, 'antecedente base desconhecido') unless BackgroundRules.slug_known?(parent_api_index)
  end

  def invalidate_rules_cache
    BackgroundRules.clear_cache!
  rescue StandardError => e
    Rails.logger.warn("Background#invalidate_rules_cache: #{e.message}")
  end
end
