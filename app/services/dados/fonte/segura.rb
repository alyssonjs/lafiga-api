# frozen_string_literal: true

module Dados
  module Fonte
    # A FONTE SEGURA (L0.6; plano B2): `SecureRandom`, para as ações do jogador. Ela não se repete; quem dá a
    # idempotência é a chave da `Rolagem` (`Dados::Rola` devolve a gravada).
    class Segura
      NOME = 'segura'

      def nome
        NOME
      end

      def d(lados)
        SecureRandom.random_number(lados) + 1
      end
    end
  end
end
