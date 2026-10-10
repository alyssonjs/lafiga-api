# frozen_string_literal: true

module Dados
  # RECONFERE uma rolagem gravada (L0.6; `bin/rails "dados:verificar[ID]"`):
  # - o SELO: ainda é o do que está gravado (nada mudou na tabela)?
  # - na fonte `hmac`, os próprios DADOS: rolar de novo com a mesma chave dá os mesmos números? Na `segura` não há como
  #   rolar de novo; vale o selo.
  module Verifica
    module_function

    Resultado = Struct.new(:ok, :selo, :dados, :linhas, keyword_init: true)

    def call(rolagem)
      selo = rolagem.selo_confere?
      dados = rolagem.fonte == Fonte::Hmac::NOME ? (rola_de_novo(rolagem) ? :conferem : :diferem) : :sem_como_rolar_de_novo
      linhas = [
        "rolagem #{rolagem.id} (#{rolagem.fonte}) #{rolagem.expressao} = #{rolagem.total}, chave #{rolagem.chave}",
        "selo: #{selo ? 'confere' : 'NÃO CONFERE'}",
        "dados: #{{ conferem: 'conferem', diferem: 'NÃO CONFEREM', sem_como_rolar_de_novo: 'fonte segura (só o selo)' }[dados]}",
      ]
      Resultado.new(ok: selo && dados != :diferem, selo: selo, dados: dados, linhas: linhas)
    end

    def rola_de_novo(rolagem)
      de_novo = Expressao.parse(rolagem.expressao).rola(Fonte::Hmac.new(rolagem.chave))
      de_novo['grupos'] == rolagem.dados && de_novo['total'] == rolagem.total
    end
  end
end
