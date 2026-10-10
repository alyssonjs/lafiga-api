# frozen_string_literal: true

module Dados
  # ROLA uma expressão e GRAVA a rolagem selada (L0.6). Idempotente pela `chave`: se ela já foi rolada, devolve a
  # rolagem gravada sem rolar de novo (o retry do cliente, a segunda aba, o reprocessamento da agenda).
  #
  # `fonte`: `:segura` (as ações do jogador) ou `:hmac` (o mundo: a chave decide os dados). O bloco, quando há, recebe o
  # resultado e devolve o que entra a mais no `detalhe` antes de selar (o teste: o natural, a margem).
  module Rola
    module_function

    def call(expressao:, chave:, fonte: :segura, detalhe: {}, contexto: {})
      chave = chave.to_s
      raise ArgumentError, 'chave vazia' if chave.empty?

      gravada = Rolagem.find_by(chave: chave)
      return gravada if gravada

      expr = expressao.is_a?(Expressao) ? expressao : Expressao.parse(expressao)
      gerador = fonte.to_s == Fonte::Hmac::NOME ? Fonte::Hmac.new(chave) : Fonte::Segura.new
      resultado = expr.rola(gerador)
      detalhe = detalhe.merge(yield(resultado)) if block_given?
      atributos = {
        chave: chave, fonte: gerador.nome, expressao: expr.to_s, dados: resultado['grupos'], total: resultado['total'],
        detalhe: detalhe, contexto: contexto,
      }
      # num savepoint: a chave repetida por outro processo não estraga a transação de quem chamou
      Rolagem.transaction(requires_new: true) { Rolagem.create!(atributos.merge(selo: Selo.de(**atributos))) }
    rescue ActiveRecord::RecordNotUnique
      Rolagem.find_by!(chave: chave)
    end
  end
end
