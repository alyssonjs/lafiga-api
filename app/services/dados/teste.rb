# frozen_string_literal: true

module Dados
  # O TESTE de d20 (L0.6; plano B2, Livro do Jogador cap. 7): o d20 mais o modificador do atributo, a proficiência
  # (dobrada na especialização) e os situacionais. Com vantagem, 2d20 e fica o maior; com desvantagem, o menor.
  #
  # Contra uma CD, diz se passou (total ≥ CD) e por quanto: a margem é a base dos graus de sucesso (A5, no L2.4). No teste
  # de atributo, o 20 e o 1 naturais não passam nem falham sozinhos; o `natural` fica no detalhe para quem precisar.
  #
  # Devolve a `Dados::Rolagem` gravada e selada. O detalhe traz cada parcela, o natural e, com CD, o sucesso e a margem.
  module Teste
    module_function

    DADO = { 'normal' => '1d20', 'vantagem' => '2d20kh1', 'desvantagem' => '2d20kl1' }.freeze

    def call(chave:, atributo: 0, proficiencia: 0, proficiente: false, especialista: false, situacional: 0,
             vantagem: 'normal', cd: nil, fonte: :segura, contexto: {})
      vantagem = vantagem.to_s
      raise ArgumentError, "vantagem inválida: #{vantagem}" unless DADO.key?(vantagem)

      bonus = proficiente ? proficiencia * (especialista ? 2 : 1) : 0
      mod = atributo + bonus + situacional
      expressao = mod.zero? ? DADO[vantagem] : "#{DADO[vantagem]}#{mod.negative? ? mod : "+#{mod}"}"
      detalhe = {
        'teste' => true, 'atributo' => atributo, 'proficiencia' => bonus,
        'especialista' => proficiente && especialista, 'situacional' => situacional, 'vantagem' => vantagem, 'cd' => cd,
      }
      Rola.call(expressao: expressao, chave: chave, fonte: fonte, detalhe: detalhe, contexto: contexto) do |r|
        natural = r['grupos'].first['mantidos'].first
        fim = { 'natural' => natural }
        fim.merge!('sucesso' => r['total'] >= cd, 'margem' => r['total'] - cd) if cd
        fim
      end
    end
  end
end
