# frozen_string_literal: true

module Subclasses
  # A BASE DO LIVRO de uma sub-classe: o nó de níveis do
  # `config/subclass_overrides.yml`, composto pelos MESMOS helpers do import.
  #
  # Para quê: com `levels_json` canônico e editável pelo mestre, a página precisa
  # mostrar o que a sub-classe vale no livro para (a) marcar que aquele nível
  # difere e (b) restaurá-lo. Sem uma base, "soltar a chave" — que no editor de
  # raças é um gesto explícito — não teria para onde voltar.
  #
  # ⚠️ Compor pelos helpers do import, e não reler o YAML à mão, é o que garante
  # que a base mostrada é a MESMA que o import gravaria: alias de classe
  # (`CLASS_ALIASES`, aplicado dentro de `merged_overrides`), alias de sub
  # (`SUBCLASS_ALIASES`) e o discriminador `levels`. `rules`, `boons` e
  # `invocations` do bruxo são estrutura da CLASSE, não arquétipos — quem os
  # tratasse como sub-classe inventaria três subs que não existem.
  module YamlBase
    NAO_SAO_SUBCLASSES = %w[boons invocations rules].freeze

    module_function

    # { api_index_de_destino => [linhas do livro] } para uma classe.
    def mapa(klass_idx)
      subs = DndImportHelpers.merged_overrides[klass_idx.to_s]
      return {} unless subs.is_a?(Hash)

      subs.each_with_object({}) do |(sub_idx, bruto), acc|
        next if NAO_SAO_SUBCLASSES.include?(sub_idx.to_s)
        next unless bruto.is_a?(Hash)

        acc[destino(klass_idx, sub_idx)] = linhas_do_no(bruto)
      end
    end

    def linhas(klass_idx, sub_api_index)
      mapa(klass_idx)[sub_api_index.to_s] || []
    end

    # O `api_index` que o import GRAVA para este nó: a chave do YAML passada pelo
    # alias. É por ele que a sub do banco se liga de volta à base do livro.
    def destino(klass_idx, sub_idx)
      DndImportHelpers::SUBCLASS_ALIASES.dig(klass_idx.to_s, sub_idx.to_s) || sub_idx.to_s
    end

    def linhas_do_no(bruto)
      Array(bruto['levels'] || bruto[:levels]).compact.select { |r| r.is_a?(Hash) }
    end
  end
end
