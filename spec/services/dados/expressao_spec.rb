# frozen_string_literal: true

require 'rails_helper'

# A gramática dos dados do servidor (L0.6): a do `!d20+1` do chat e a do rolador do front (`DiceRoller.tsx`), com o
# sinal de cada termo valendo de verdade.
RSpec.describe Dados::Expressao do
  # uma fonte de mentira, que devolve os números na ordem
  def fonte(*numeros)
    fila = numeros.dup
    Class.new { define_method(:d) { |_lados| fila.shift } }.new
  end

  it 'lê as formas do chat e do rolador, e escreve a forma canônica' do
    expect(described_class.parse('d20+1').to_s).to eq('1d20+1')
    expect(described_class.parse(' 2D6 - 1 ').to_s).to eq('2d6-1')
    expect(described_class.parse('2d20kh1+3').to_s).to eq('2d20kh1+3')
    expect(described_class.parse('1d8+1d6+2').to_s).to eq('1d8+1d6+2')
    expect(described_class.parse('1d20-1d4').to_s).to eq('1d20-1d4')
    expect(described_class.parse('3+1d4').to_s).to eq('1d4+3')
  end

  it 'soma e subtrai cada termo pelo seu sinal' do
    r = described_class.parse('1d20-1d4+2').rola(fonte(15, 3))
    expect(r['total']).to eq(15 - 3 + 2)
    expect(r['grupos'].map { |g| [g['dado'], g['sinal'], g['rolagens']] }).to eq([['1d20', 1, [15]], ['1d4', -1, [3]]])
  end

  it 'mantém os maiores ou os menores (vantagem e desvantagem)' do
    vantagem = described_class.parse('2d20kh1+3').rola(fonte(7, 15))
    expect(vantagem['grupos'].first).to include('rolagens' => [7, 15], 'mantidos' => [15])
    expect(vantagem['total']).to eq(18)

    desvantagem = described_class.parse('2d20kl1').rola(fonte(7, 15))
    expect(desvantagem['total']).to eq(7)

    tres_maiores = described_class.parse('4d6kh3').rola(fonte(1, 5, 3, 6))
    expect(tres_maiores['grupos'].first['mantidos']).to eq([5, 3, 6])
    expect(tres_maiores['total']).to eq(14)
  end

  it 'escreve o resultado por extenso' do
    r = described_class.parse('2d20kh1+3').rola(fonte(7, 15))
    expect(described_class.texto(grupos: r['grupos'], modificador: 3, total: r['total'])).to eq('2d20kh1 (7, 15 → 15) + 3 = 18')

    r = described_class.parse('1d8-1d4').rola(fonte(5, 2))
    expect(described_class.texto(grupos: r['grupos'], modificador: 0, total: r['total'])).to eq('1d8 (5) - 1d4 (2) = 3')
  end

  it 'recusa o que não é expressão de dados, e os exageros' do
    ['', 'oi', '5', 'd', '1d0', '101d6', '1d1001', '2d20kh3', 'd20+x', '1d20*2', (['1d6'] * 11).join('+'),
     "d20+#{'1' * 100}"].each do |texto|
      expect { described_class.parse(texto) }.to raise_error(described_class::Invalida), texto.inspect
    end
  end
end
