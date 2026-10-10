# frozen_string_literal: true

module Dados
  # O SELO de uma rolagem (L0.6): o HMAC-SHA256, com o segredo dos dados, de tudo o que foi rolado. Mudou um número na
  # tabela, o selo deixa de bater (`dados:verificar`).
  module Selo
    module_function

    def de(chave:, fonte:, expressao:, dados:, total:, detalhe:, contexto:)
      corpo = JSON.generate([chave.to_s, fonte.to_s, expressao.to_s, canonico(dados), total, canonico(detalhe), canonico(contexto)])
      OpenSSL::HMAC.hexdigest('SHA256', Dados.segredo, "selo:#{corpo}")
    end

    # as chaves em ordem e como texto: o jsonb do Postgres não guarda a ordem nem o símbolo
    def canonico(valor)
      case valor
      when Hash then valor.to_h { |k, v| [k.to_s, canonico(v)] }.sort.to_h
      when Array then valor.map { |v| canonico(v) }
      when Symbol then valor.to_s
      else valor
      end
    end
  end
end
