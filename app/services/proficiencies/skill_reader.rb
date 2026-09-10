# frozen_string_literal: true

module Proficiencies
  # Leitura de PERÍCIA pelo catálogo. Contrato em `CatalogReader`.
  #
  # O tipo mais limpo dos oito: as quatro fontes já concordavam nas mesmas 18.
  # O que o catálogo acrescenta é tolerância a acento e caixa — "Intuicao" e
  # "INTUIÇÃO" passam a resolver para "Intuição".
  class SkillReader < CatalogReader
    CATEGORY = 'skill'

    def self.categories = [CATEGORY]
  end
end
