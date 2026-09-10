# frozen_string_literal: true

# Grafia alternativa que resolve para uma proficiência do catálogo.
#
# Existe porque o dado já gravado nas fichas é STRING e não vai ser reescrito
# na fase 0 — sem apelido, catalogar seria migração destrutiva.
class ProficiencyAlias < ApplicationRecord
  belongs_to :proficiency

  validates :alias_key, presence: true, uniqueness: true
end
