# frozen_string_literal: true

module Proficiencies
  # Leitura de IDIOMA pelo catálogo. Contrato e garantias em `CatalogReader`.
  class LanguageReader < CatalogReader
    CATEGORY = 'language'

    def self.categories = [CATEGORY]
  end
end
