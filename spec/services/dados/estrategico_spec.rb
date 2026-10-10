# frozen_string_literal: true

require 'rails_helper'

# O d100 estratégico (L0.7): a chance é a base mais os fatores, presa entre o piso e o teto; acontece quando o d100 cai
# na chance ou abaixo. Os números sorteados mudam a cada máquina (o segredo vem do secret_key_base), então as
# expectativas são sobre as contas.
RSpec.describe Dados::Estrategico do
  it 'soma a base e os fatores (com as vezes) e grava tudo no detalhe' do
    r = described_class.call(
      chave: 'e:1', base: 5,
      fatores: [{ 'nome' => 'população alta', 'valor' => 10, 'vezes' => 2 }, { nome: 'poço', valor: -10 }],
    )

    expect(r.expressao).to eq('1d100')
    expect(r.detalhe).to include('estrategico' => true, 'base' => 5, 'chance' => 15, 'piso' => 0, 'teto' => 100)
    expect(r.detalhe['fatores']).to eq([
      { 'nome' => 'população alta', 'valor' => 10, 'vezes' => 2, 'soma' => 20 },
      { 'nome' => 'poço', 'valor' => -10, 'vezes' => 1, 'soma' => -10 },
    ])
    expect(r.detalhe['rolado']).to eq(r.total)
    expect(r.detalhe['acontece']).to eq(r.total <= 15)
    expect(r.detalhe['margem']).to eq(15 - r.total)
  end

  it 'prende a chance entre o piso e o teto' do
    expect(described_class.call(chave: 'e:2', base: 5, fatores: [{ 'valor' => -50 }], piso: 1).detalhe['chance']).to eq(1)
    expect(described_class.call(chave: 'e:3', base: 90, fatores: [{ 'valor' => 50 }], teto: 95).detalhe['chance']).to eq(95)
  end

  it 'chance 0 nunca acontece; chance 100, sempre' do
    20.times do |i|
      expect(described_class.call(chave: "e:zero:#{i}", base: 0).detalhe['acontece']).to be(false)
      expect(described_class.call(chave: "e:cem:#{i}", base: 100).detalhe['acontece']).to be(true)
    end
  end

  it 'fonte fixa (hmac, a mesma chave) dá o mesmo resultado, e se reconfere' do
    a = described_class.call(chave: 'mundo:1:evento:doenca:7', base: 30)
    b = described_class.call(chave: 'mundo:1:evento:doenca:7', base: 30)

    expect(b.id).to eq(a.id)
    expect(a.fonte).to eq('hmac')
    de_novo = Dados::Expressao.parse('1d100').rola(Dados::Fonte::Hmac.new('mundo:1:evento:doenca:7'))
    expect(a.total).to eq(de_novo['total'])
    expect(Dados::Verifica.call(a).to_h).to include(ok: true, dados: :conferem)
  end

  it 'recusa o que não é inteiro e os limites fora de 0..100' do
    expect { described_class.call(chave: 'e:4', base: 5.5) }.to raise_error(ArgumentError)
    expect { described_class.call(chave: 'e:5', base: 5, fatores: [{ 'valor' => 1.5 }]) }.to raise_error(ArgumentError)
    expect { described_class.call(chave: 'e:6', base: 5, piso: 50, teto: 40) }.to raise_error(ArgumentError)
    expect { described_class.call(chave: 'e:7', base: 5, teto: 101) }.to raise_error(ArgumentError)
  end
end
