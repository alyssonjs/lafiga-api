# frozen_string_literal: true

module Proficiencies
  # Quantas fichas citam cada proficiência do catálogo.
  #
  # ⚠️ Existe porque a ficha referencia proficiência por STRING, não por chave
  # estrangeira. O banco não impede apagar uma linha em uso: ela some e toda
  # ficha que a citava vira órfã EM SILÊNCIO — o mesmo modo de falha que custou
  # as quatro grafias de "Veículos terrestres" e 14 proficiências perdidas.
  #
  # Como não há FK para contar, a contagem passa por resolução de apelido: é a
  # única forma de saber que a ficha que guarda "Veículos Terrestres" está a
  # usar a linha "Veículos (terrestres)".
  class UsageCounter
    CAMPOS_CLASS_SUMMARY = %w[tools weapon_proficiencies armor_proficiencies skills saving_throws].freeze

    # { proficiency_id => nº de fichas }
    #
    # Conta FICHA, não ocorrência: uma ficha que cite a mesma proficiência em
    # dois campos conta uma vez. É o número que responde "quem quebra se eu
    # apagar isto".
    def self.by_proficiency_id
      contagem = Hash.new(0)
      Sheet.find_each do |sheet|
        ids = Set.new
        brutos(sheet).each do |valor|
          linha = Proficiency.resolve(valor.to_s)
          ids << linha.id if linha
        end
        ids.each { |id| contagem[id] += 1 }
      end
      contagem
    end

    def self.brutos(sheet)
      cs = sheet.class_summary || {}
      rs = sheet.race_summary || {}
      meta = sheet.metadata || {}
      CAMPOS_CLASS_SUMMARY.flat_map { |c| Array(cs[c]) } +
        Array(rs['languages']) +
        # ⚠️ O balde do antecedente mistura cinco tipos sem etiqueta; entra
        # inteiro porque a resolução é que decide o que é o quê.
        Array(meta['background_proficiencies'])
    end
  end
end
