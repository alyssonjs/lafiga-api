# frozen_string_literal: true

module Proficiencies
  # Leitura de ARMADURA pelo catálogo. Contrato em `CatalogReader`.
  #
  # Três vocabulários convergem aqui: a ficha guarda slug inglês ("light"),
  # `race_rules.yml` guarda pt-BR ("leve"), e o que se exibe é "Armaduras
  # Leves" — o canônico.
  #
  # ⚠️ Mudar o valor EMITIDO é seguro porque o front já passava tudo por
  # `prettifyProficiencyList`, que converte "light" para exatamente o mesmo
  # "Armaduras Leves". A saída final não muda; o que muda é deixar de depender
  # de um tradutor no front.
  class ArmorReader < CatalogReader
    CATEGORY = 'armor'

    def self.categories = [CATEGORY]
  end
end
