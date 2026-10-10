# frozen_string_literal: true

module Dados
  # A EXPRESSÃO de dados (L0.6). Extraída do `!d20+1` do chat (`Chat::CommandProcessor`), com a gramática do rolador do
  # front (`DiceRoller.tsx`): grupos `NdL`, com `khN`/`klN` (manter os N maiores ou menores: a vantagem é `2d20kh1`), e
  # modificadores inteiros. Cada termo soma ou subtrai pelo seu sinal: `1d8+1d6+2`, `2d6-1`, `1d20-1d4`.
  #
  # Rolar não sorteia nada aqui: quem dá os dados é a `fonte` (`Fonte::Segura` ou `Fonte::Hmac`).
  class Expressao
    MAX_QUANTIDADE = 100
    MAX_LADOS = 1000
    MAX_GRUPOS = 10
    MAX_TEXTO = 100

    class Invalida < ArgumentError; end

    Grupo = Struct.new(:sinal, :quantidade, :lados, :manter, :manter_qtd, keyword_init: true) do
      def to_s
        "#{quantidade}d#{lados}#{manter ? "k#{manter}#{manter_qtd}" : ''}"
      end
    end

    attr_reader :grupos, :modificador

    def self.parse(texto)
      new(texto)
    end

    # o resultado por extenso: `2d20kh1 (7, 15 → 15) + 3 = 18`, `1d8 (5) - 1d4 (2) = 3`
    def self.texto(grupos:, modificador:, total:)
      partes = grupos.each_with_index.map do |g, i|
        dados = g['rolagens'].join(', ')
        dados += " → #{g['mantidos'].join(', ')}" if g['mantidos'].size != g['rolagens'].size
        sinal = if g['sinal'].negative? then '- '
                elsif i.zero? then ''
                else '+ '
                end
        "#{sinal}#{g['dado']} (#{dados})"
      end
      partes << "#{modificador.negative? ? '-' : '+'} #{modificador.abs}" unless modificador.zero?
      "#{partes.join(' ')} = #{total}"
    end

    def initialize(texto)
      bruto = texto.to_s.downcase.gsub(/\s+/, '')
      raise Invalida, 'expressão vazia' if bruto.empty?
      raise Invalida, 'expressão longa demais' if bruto.length > MAX_TEXTO
      raise Invalida, "expressão inválida: #{texto}" unless bruto.match?(/\A[+-]?[0-9dkhl]+(?:[+-][0-9dkhl]+)*\z/)

      @grupos = []
      @modificador = 0
      bruto.scan(/([+-]?)([^+-]+)/) { |sinal, termo| termo!(sinal == '-' ? -1 : 1, termo) }
      raise Invalida, 'expressão sem dados' if @grupos.empty?
      raise Invalida, "mais de #{MAX_GRUPOS} grupos de dados" if @grupos.size > MAX_GRUPOS
    end

    # A forma canônica, a que se grava: `2d20kh1+3`, `1d8-1d4+2`.
    def to_s
      partes = @grupos.each_with_index.map do |g, i|
        sinal = if g.sinal.negative? then '-'
                elsif i.zero? then ''
                else '+'
                end
        "#{sinal}#{g}"
      end
      partes << (@modificador.negative? ? @modificador.to_s : "+#{@modificador}") unless @modificador.zero?
      partes.join
    end

    # Rola com a `fonte` (`#d(lados)`).
    # → { 'grupos' => [{ 'dado', 'sinal', 'rolagens', 'mantidos' }], 'modificador', 'total' }
    def rola(fonte)
      grupos = @grupos.map do |g|
        rolagens = Array.new(g.quantidade) { fonte.d(g.lados) }
        { 'dado' => g.to_s, 'sinal' => g.sinal, 'rolagens' => rolagens, 'mantidos' => mantidos(rolagens, g) }
      end
      total = grupos.sum { |g| g['sinal'] * g['mantidos'].sum } + @modificador
      { 'grupos' => grupos, 'modificador' => @modificador, 'total' => total }
    end

    private

    def termo!(sinal, termo)
      if (m = termo.match(/\A(\d*)d(\d+)(?:k([hl])(\d+))?\z/))
        quantidade = m[1].empty? ? 1 : m[1].to_i
        lados = m[2].to_i
        manter_qtd = m[4]&.to_i
        raise Invalida, "quantidade de dados fora de 1..#{MAX_QUANTIDADE}" unless quantidade.between?(1, MAX_QUANTIDADE)
        raise Invalida, "lados fora de 1..#{MAX_LADOS}" unless lados.between?(1, MAX_LADOS)
        raise Invalida, 'manter mais dados do que rolou' if manter_qtd && !manter_qtd.between?(1, quantidade)

        @grupos << Grupo.new(sinal: sinal, quantidade: quantidade, lados: lados, manter: m[3], manter_qtd: manter_qtd)
      elsif termo.match?(/\A\d+\z/)
        @modificador += sinal * termo.to_i
      else
        raise Invalida, "termo inválido: #{termo}"
      end
    end

    # os mantidos, na ordem em que saíram (empate: o primeiro)
    def mantidos(rolagens, grupo)
      return rolagens.dup unless grupo.manter

      ordem = rolagens.each_with_index.sort_by { |v, i| [grupo.manter == 'h' ? -v : v, i] }
      fica = ordem.first(grupo.manter_qtd).map(&:last).to_set
      rolagens.each_with_index.select { |_, i| fica.include?(i) }.map(&:first)
    end
  end
end
