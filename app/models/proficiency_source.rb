# frozen_string_literal: true

# Uma fonte que concede uma proficiência. Ver a migration para o porquê de ser
# REGISTRO e não autoridade.
class ProficiencySource < ApplicationRecord
  belongs_to :proficiency

  TYPES = %w[race sub_race klass sub_klass background feat].freeze
  TYPE_LABELS = {
    'race' => 'Raça', 'sub_race' => 'Sub-raça', 'klass' => 'Classe',
    'sub_klass' => 'Subclasse', 'background' => 'Antecedente', 'feat' => 'Talento'
  }.freeze

  ORIGINS = %w[derived manual].freeze

  validates :source_type, presence: true, inclusion: { in: TYPES }
  validates :source_key, presence: true
  validates :origin, inclusion: { in: ORIGINS }
  validates :source_key, uniqueness: { scope: %i[proficiency_id source_type] }

  scope :derived, -> { where(origin: 'derived') }
  scope :manual, -> { where(origin: 'manual') }

  def label
    "#{TYPE_LABELS[source_type] || source_type}: #{source_name.presence || source_key}"
  end
end
