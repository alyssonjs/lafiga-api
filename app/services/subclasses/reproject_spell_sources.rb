# frozen_string_literal: true

module Subclasses
  # Reprojeta os `SpellSource` de "sempre preparada" de uma sub-classe a partir
  # do `levels_json` JÁ GRAVADO.
  #
  # Por que existe: a derivação morava dentro de `apply_subclass_grants!`, que só
  # roda no import. Com a página do compêndio editando `grants.spells`, mexer nas
  # magias de uma sub-classe não mexeria em `SpellSource` nenhum — e é dele que a
  # ficha tira as sempre preparadas. O mestre veria a regra nova na página e a
  # ficha continuaria com a lista velha, sem erro em lugar nenhum.
  #
  # ⚠️ Só as linhas `always_prepared` são refeitas. As de `notes: 'expanded'`
  # nascem do nó `expanded_spells` do TOPO da sub no YAML, fora do `levels_json`:
  # apagá-las aqui perderia dado que esta classe não sabe reconstruir.
  #
  # ⚠️ Paridade com o import DE PROPÓSITO: lê `grants.spells.always_prepared` na
  # linha do nível, não dentro de cada feature. Os leitores da ficha olham os
  # dois lugares, mas o import só projetou o primeiro — inventar o segundo aqui
  # criaria atrelagens que nunca existiram, em silêncio e para todas as fichas.
  module ReprojectSpellSources
    Relatorio = Struct.new(:criadas, :atualizadas, :removidas, :nao_resolvidas, keyword_init: true)

    module_function

    def call(sub_klass)
      desejadas, nao_resolvidas = desejadas_de(sub_klass)
      atuais = SpellSource.where(source_type: 'SubKlass', source_id: sub_klass.id, always_prepared: true)
                          .index_by(&:spell_id)

      removidas = (atuais.keys - desejadas.keys).each { |id| atuais[id].destroy! }.size
      criadas = 0
      atualizadas = 0

      desejadas.each do |spell_id, min_lvl|
        fonte = atuais[spell_id] ||
                SpellSource.new(source_type: 'SubKlass', source_id: sub_klass.id, spell_id: spell_id)
        fonte.always_prepared = true
        fonte.min_class_level = min_lvl
        nova = fonte.new_record?
        next unless fonte.changed? || nova

        fonte.save!
        nova ? criadas += 1 : atualizadas += 1
      end

      Relatorio.new(criadas: criadas, atualizadas: atualizadas, removidas: removidas,
                    nao_resolvidas: nao_resolvidas)
    end

    # { spell_id => min_class_level } + os rótulos que não casaram com magia
    # nenhuma (relatados, nunca descartados em silêncio).
    def desejadas_de(sub_klass)
      desejadas = {}
      nao_resolvidas = []

      sub_klass.linhas_de_nivel.each do |linha|
        mapa = linha.dig('grants', 'spells', 'always_prepared')
        next unless mapa.is_a?(Hash)

        mapa.each do |nivel_minimo, nomes|
          minimo = nivel_minimo.to_i
          Array(nomes).each do |nome|
            magia = resolve(nome)
            next nao_resolvidas << nome.to_s if magia.nil?

            desejadas[magia.id] = minimo.positive? ? minimo : nil
          end
        end
      end

      [desejadas, nao_resolvidas.uniq]
    end

    # A MESMA escada do import, agora num lugar só: nome exato, api_index,
    # tabela de tradução (o YAML fala slug em inglês e a regra fala PT),
    # slug derivado do nome e, por último, nome sem diferenciar maiúsculas.
    def resolve(rotulo)
      nome = rotulo.to_s.strip
      return nil if nome.blank?

      Spell.find_by(name: nome) ||
        Spell.find_by(api_index: nome) ||
        por_traducao(nome) ||
        Spell.find_by(api_index: slug(nome)) ||
        Spell.where('LOWER(name) = ?', nome.downcase).first
    end

    def por_traducao(nome)
      chave = traducao[:por_nome][nome] || traducao[:por_nome_ci][nome.downcase]
      chave && Spell.find_by(api_index: chave)
    end

    # Memoizado: é arquivo de configuração, muda por deploy. O import relia o
    # YAML uma vez POR LINHA DE NÍVEL de cada sub-classe.
    def traducao
      @traducao ||= begin
        caminho = Rails.root.join('config', 'dnd_translations.yml')
        magias = ((File.exist?(caminho) ? YAML.load_file(caminho) : nil) || {})['spells'] || {}
        {
          por_nome: magias.invert,
          por_nome_ci: magias.each_with_object({}) { |(chave, pt), h| h[pt.to_s.downcase] = chave }
        }
      end
    end

    def esquece_traducao!
      @traducao = nil
    end

    def slug(nome)
      ActiveSupport::Inflector.transliterate(nome.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
    end
  end
end
