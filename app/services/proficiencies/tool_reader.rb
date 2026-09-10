# frozen_string_literal: true

module Proficiencies
  # Leitura de FERRAMENTA (e VEÍCULO) pelo catálogo.
  #
  # ⚠️ Aceita as DUAS categorias de propósito. No catálogo veículo é tipo
  # próprio — a proficiência é "Veículos (terrestres)", não "Carroça" —, mas a
  # ficha sempre guardou os dois no MESMO array (`class_summary.tools`), porque
  # veículo nunca teve casa. Um leitor que só aceitasse `tool` deixaria
  # "Veículos Terrestres" órfão justamente na proficiência que já custou 14
  # órfãs por causa de grafia.
  #
  # Contrato e garantias em `CatalogReader`.
  class ToolReader < CatalogReader
    CATEGORIES = %w[tool vehicle].freeze

    def self.categories = CATEGORIES
  end
end
