# frozen_string_literal: true

require 'rails_helper'

# As fontes de sorte (L0.6): a determinística (`Hmac`, pela chave) e a segura (`SecureRandom`).
RSpec.describe 'Dados::Fonte' do
  def sequencia(fonte, quantos, lados)
    Array.new(quantos) { fonte.d(lados) }
  end

  describe Dados::Fonte::Hmac do
    it 'a mesma chave dá os mesmos dados; outra chave, outros' do
      a = sequencia(described_class.new('mundo:1:evento:7'), 20, 20)
      b = sequencia(described_class.new('mundo:1:evento:7'), 20, 20)
      c = sequencia(described_class.new('mundo:1:evento:8'), 20, 20)

      expect(a).to eq(b)
      expect(a).not_to eq(c)
    end

    it 'outro segredo, outros dados' do
      chave = 'mundo:1:evento:7'
      expect(sequencia(described_class.new(chave, segredo: 'um'), 20, 20))
        .not_to eq(sequencia(described_class.new(chave, segredo: 'outro'), 20, 20))
    end

    it 'cai sempre entre 1 e o número de lados, e passa por todas as faces' do
      d6 = sequencia(described_class.new('faces'), 600, 6)
      expect(d6.minmax).to eq([1, 6])
      expect(d6.tally.size).to eq(6)
      expect(sequencia(described_class.new('d1000'), 200, 1000)).to all(be_between(1, 1000))
    end
  end

  describe Dados::Fonte::Segura do
    it 'cai sempre entre 1 e o número de lados' do
      expect(sequencia(described_class.new, 600, 6).minmax).to eq([1, 6])
    end
  end
end
