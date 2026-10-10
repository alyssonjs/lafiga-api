# frozen_string_literal: true

module Dados
  module Fonte
    # A FONTE DETERMINÍSTICA (L0.6; plano B2). Os dados saem do HMAC-SHA256 do segredo com a CHAVE e o número do dado:
    # a mesma chave dá os mesmos dados, em qualquer processo do ambiente. É o que deixa a agenda do mundo reprocessar
    # um evento e chegar ao mesmo resultado (plano D11), e o `dados:verificar` rolar de novo para conferir.
    #
    # Sem viés: o número de 64 bits que cai na sobra (acima do maior múltiplo de `lados`) é descartado, e vale o próximo.
    class Hmac
      NOME = 'hmac'
      LIMITE = 2**64

      attr_reader :chave

      def initialize(chave, segredo: Dados.segredo)
        @chave = chave.to_s
        @segredo = segredo
        @n = 0
      end

      def nome
        NOME
      end

      def d(lados)
        teto = LIMITE - (LIMITE % lados)
        loop do
          x = OpenSSL::HMAC.digest('SHA256', @segredo, "#{@chave}:#{@n}").unpack1('Q>')
          @n += 1
          return (x % lados) + 1 if x < teto
        end
      end
    end
  end
end
