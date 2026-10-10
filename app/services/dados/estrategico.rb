# frozen_string_literal: true

module Dados
  # O d100 ESTRATÉGICO (09/10; L0.7, plano B2 e I7, GDD §103 e §116). A chance é a soma do estado do mundo: uma base e
  # os fatores, cada um com o seu peso (e quantas vezes vale), presa entre um piso e um teto. Só depois se rola o d100,
  # e acontece (ou dá certo) quando ele cai na chance ou abaixo. A margem (chance − rolado) fica para quem precisar de
  # graus.
  #
  # Grava a rolagem selada (`Dados::Rola`) com tudo no detalhe: a base, cada fator, o piso, o teto, a chance, o rolado,
  # o resultado e a margem. Fonte: `:hmac` no mundo (a chave do evento decide o dado), `:segura` numa ação do jogador.
  module Estrategico
    module_function

    # `fatores`: [{ 'nome', 'valor' (pontos de chance, + ou −), 'vezes' (1 se ausente), 'chave'? }]
    def call(chave:, base:, fatores: [], piso: 0, teto: 100, fonte: :hmac, contexto: {})
      inteiros!(base: base, piso: piso, teto: teto)
      raise ArgumentError, "piso e teto fora de 0..100: #{piso}..#{teto}" unless piso.between?(0, 100) && teto.between?(piso, 100)

      fatores = fatores.map { |f| fator(f) }
      chance = (base + fatores.sum { |f| f['soma'] }).clamp(piso, teto)
      detalhe = {
        'estrategico' => true, 'base' => base, 'fatores' => fatores, 'piso' => piso, 'teto' => teto, 'chance' => chance,
      }
      Rola.call(expressao: '1d100', chave: chave, fonte: fonte, detalhe: detalhe, contexto: contexto) do |r|
        rolado = r['total']
        { 'rolado' => rolado, 'acontece' => rolado <= chance, 'margem' => chance - rolado }
      end
    end

    def fator(bruto)
      f = bruto.to_h.transform_keys(&:to_s)
      vezes = f.fetch('vezes', 1)
      inteiros!(valor: f['valor'], vezes: vezes)
      raise ArgumentError, "vezes negativo: #{vezes}" if vezes.negative?

      f.slice('chave', 'nome').merge('valor' => f['valor'], 'vezes' => vezes, 'soma' => f['valor'] * vezes)
    end

    # só inteiros (plano D11): a chance em pontos percentuais
    def inteiros!(**valores)
      valores.each { |nome, v| raise ArgumentError, "#{nome} deve ser inteiro: #{v.inspect}" unless v.is_a?(Integer) }
    end
  end
end
