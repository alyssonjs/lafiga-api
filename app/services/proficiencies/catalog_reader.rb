# frozen_string_literal: true

module Proficiencies
  # FASE 1 do catálogo — base de quem LÊ proficiência pelo catálogo em vez de
  # pela grafia exata.
  #
  # Nada aqui muda o que é GRAVADO: a ficha continua a guardar a string que
  # sempre guardou. O que muda é que a leitura deixa de depender de alguém ter
  # digitado o acento certo — que é o modo de falha que órfãou 14 proficiências
  # sem ninguém notar.
  #
  # Três propriedades são load-bearing, e cada uma existe por um motivo:
  #
  #   1. TOLERANTE — o que não resolve passa INTACTO. Descartar seria trocar um
  #      defeito silencioso (a linha some da ficha) por outro pior (some de
  #      propósito). Quem aponta o não-catalogado é a auditoria, não o leitor.
  #   2. DEGRADA PARA IDENTIDADE — com o catálogo vazio devolve a entrada como
  #      está. O código sobe para produção ANTES de o seed rodar; sem isto, a
  #      janela entre os dois deixaria toda ficha sem proficiência.
  #   3. PRESERVA A ORDEM — primeira ocorrência vence. A ficha não pode
  #      reembaralhar a lista só porque passou a resolver.
  #
  # Subclasse declara `categories`. Ver `LanguageReader` e `ToolReader`.
  class CatalogReader
    class << self
      # Categorias do catálogo que este leitor aceita. Mais de uma quando a
      # ficha mistura tipos no mesmo array — é o caso de ferramenta e veículo.
      def categories
        raise NotImplementedError, "#{name} precisa declarar `categories`"
      end

      # ['elfico', 'Élfico', 'Klingon'] → ['Élfico', 'Klingon']
      #
      # Colapsa por IDENTIDADE canônica, não por string: é isso que faz duas
      # grafias da mesma proficiência virarem uma linha só na ficha.
      # `Array#uniq` sozinho deixava as duas.
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

      # Mesma resolução, com a estrutura que o catálogo acrescenta.
      def detail(raws)
        canonicalize(raws).map do |nome|
          linha = lookup(nome)
          {
            'name' => nome,
            'api_index' => linha&.api_index,
            'category' => linha&.category,
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
      # por ficha. O catálogo é pequeno (142 linhas) e muda por rake, então a
      # chave de invalidação é (contagem, maior updated_at) — uma consulta
      # barata em vez de N.
      def alias_map
        assinatura = catalog_signature
        return @alias_map if defined?(@alias_map) && @alias_signature == assinatura

        linhas = Proficiency.where(category: categories).includes(:proficiency_aliases)
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
        escopo = Proficiency.where(category: categories)
        [escopo.count, escopo.maximum(:updated_at)&.to_f]
      rescue ActiveRecord::StatementInvalid
        nil
      end
    end
  end
end
