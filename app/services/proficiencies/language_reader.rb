# frozen_string_literal: true

module Proficiencies
  # FASE 1 do catálogo — quem LÊ idioma passa a resolver pelo catálogo.
  #
  # Nada aqui muda o que é GRAVADO: a ficha continua a guardar a string que
  # sempre guardou. O que muda é que a leitura deixa de depender da grafia
  # exata — "elfico", "Élfico" e "  ÉLFICO " passam a ser a mesma coisa.
  #
  # Três propriedades são load-bearing, e cada uma existe por um motivo:
  #
  #   1. TOLERANTE — o que não resolve passa INTACTO. Descartar seria trocar
  #      um defeito silencioso (a linha some) por outro pior (a linha some e
  #      agora é de propósito). A auditoria é que aponta o não-catalogado.
  #   2. DEGRADA PARA IDENTIDADE — com o catálogo vazio, devolve a entrada como
  #      está. O código sobe para produção ANTES de o seed rodar; sem isto, a
  #      janela entre os dois deixaria toda ficha sem idioma.
  #   3. PRESERVA A ORDEM — primeira ocorrência vence. A ficha não pode
  #      reembaralhar a lista de idiomas só porque passou a resolver.
  class LanguageReader
    CATEGORY = 'language'

    class << self
      # ['elfico', 'Élfico', 'Klingon'] → ['Élfico', 'Klingon']
      #
      # Colapsa por IDENTIDADE canônica, não por string: é isso que faz duas
      # grafias do mesmo idioma virarem uma linha só na ficha. `Array#uniq`
      # sozinho deixava as duas.
      def canonicalize(raws)
        vistos = {}
        Array(raws).each do |raw|
          s = raw.to_s.strip
          next if s.empty?

          linha = lookup(s)
          chave = linha ? "id:#{linha.id}" : "raw:#{Proficiency.normalize(s)}"
          vistos[chave] ||= linha&.name || s
        end
        vistos.values
      end

      # Mesma resolução, com a estrutura que o catálogo acrescenta. Para quem
      # quiser agrupar por tipo ou mostrar a relação dialeto <-> Primordial.
      def detail(raws)
        canonicalize(raws).map do |nome|
          linha = lookup(nome)
          {
            'name' => nome,
            'api_index' => linha&.api_index,
            'sub_category' => linha&.sub_category,
            'catalogued' => !linha.nil?,
          }
        end
      end

      def lookup(raw)
        mapa = alias_map
        return nil if mapa.empty?

        mapa[Proficiency.normalize(raw)]
      end

      # Mapa apelido-normalizado → Proficiency, em memória.
      #
      # ⚠️ Sem isto seria uma consulta por string, e `build_proficiencies` roda
      # por ficha. O catálogo é minúsculo (27 linhas) e muda por rake, então a
      # chave de invalidação é (contagem, maior updated_at) — uma consulta
      # barata em vez de N.
      def alias_map
        assinatura = catalog_signature
        return @alias_map if defined?(@alias_map) && @alias_signature == assinatura

        linhas = Proficiency.of(CATEGORY).includes(:proficiency_aliases)
        @alias_map = linhas.each_with_object({}) do |p, h|
          p.proficiency_aliases.each { |a| h[a.alias_key] = p }
        end.freeze
        @alias_signature = assinatura
        @alias_map
      rescue ActiveRecord::StatementInvalid
        # A tabela ainda não existe (deploy antes da migration). Identidade.
        {}.freeze
      end

      def reset_cache!
        remove_instance_variable(:@alias_map) if defined?(@alias_map)
        remove_instance_variable(:@alias_signature) if defined?(@alias_signature)
      end

      private

      def catalog_signature
        escopo = Proficiency.of(CATEGORY)
        [escopo.count, escopo.maximum(:updated_at)&.to_f]
      rescue ActiveRecord::StatementInvalid
        nil
      end
    end
  end
end
