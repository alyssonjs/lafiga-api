# frozen_string_literal: true

module Dados
  # Uma ROLAGEM do servidor (L0.6; tabela `rolagens`, plano B2): o que foi rolado, por qual fonte, com o selo.
  # Grava-se pelo `Dados::Rola`. SÓ ENTRA: depois de gravada não muda nem some, para o feed e o `dados:verificar`
  # poderem confiar nela.
  class Rolagem < ApplicationRecord
    self.table_name = 'rolagens'

    FONTES = %w[segura hmac].freeze

    validates :chave, :expressao, :selo, presence: true
    validates :fonte, inclusion: { in: FONTES }
    validates :total, numericality: { only_integer: true }

    def readonly?
      persisted? || super
    end

    # o selo gravado ainda é o do que está gravado?
    def selo_confere?
      esperado = Selo.de(chave: chave, fonte: fonte, expressao: expressao, dados: dados, total: total,
                         detalhe: detalhe, contexto: contexto)
      ActiveSupport::SecurityUtils.secure_compare(esperado, selo.to_s)
    end
  end
end
