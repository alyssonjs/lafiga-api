# frozen_string_literal: true

module Proficiencies
  # Leitura de ARMA pelo catálogo. Contrato em `CatalogReader`.
  #
  # ⚠️ Aceita `weapon` E `weapon_category`. A ficha guarda os dois no MESMO
  # array — ["simple", "hand_crossbow", "longsword", "rapieiras", "shortsword"]
  # é categoria + arma + arma + arma-em-pt-BR-plural + arma, tudo junto. Nunca
  # houve separação, e um leitor de um tipo só deixaria metade órfã.
  class WeaponReader < CatalogReader
    CATEGORIES = %w[weapon weapon_category].freeze

    def self.categories = CATEGORIES
  end
end
