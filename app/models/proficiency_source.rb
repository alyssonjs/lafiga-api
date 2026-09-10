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

  # ⚠️ FIXA = a fonte sempre concede. ESCOLHA = a proficiência é uma das opções
  # de um pool ("o anão escolhe 1 entre ferreiro, cervejeiro e pedreiro").
  # Tratar as duas igual faz o índice mentir por omissão em dois terços dos
  # casos — medido: 144 de escolha contra 94 fixas.
  GRANT_MODES = %w[fixed choice].freeze

  validates :source_type, presence: true, inclusion: { in: TYPES }
  validates :source_key, presence: true
  validates :origin, inclusion: { in: ORIGINS }
  validates :grant_mode, inclusion: { in: GRANT_MODES }
  # `choose_count` só faz sentido num pool, e só positivo.
  validates :choose_count, numericality: { greater_than: 0, allow_nil: true }
  validate :choose_count_belongs_to_choice
  validates :source_key, uniqueness: { scope: %i[proficiency_id source_type] }

  scope :derived, -> { where(origin: 'derived') }
  scope :manual, -> { where(origin: 'manual') }

  scope :fixed, -> { where(grant_mode: 'fixed') }
  scope :choice, -> { where(grant_mode: 'choice') }

  def label
    base = "#{TYPE_LABELS[source_type] || source_type}: #{source_name.presence || source_key}"
    return base if grant_mode != 'choice'

    # "(1 de N)" seria mentira: o N do pool não vive aqui, e inventá-lo é pior
    # do que omitir. O que se sabe é quantas se escolhem.
    base + (choose_count ? " (escolhe #{choose_count})" : ' (escolha)')
  end

  private

  def choose_count_belongs_to_choice
    return if choose_count.blank? || grant_mode == 'choice'

    errors.add(:choose_count, 'só se aplica a fonte de escolha')
  end
end
