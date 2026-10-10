# frozen_string_literal: true

require 'rails_helper'

# Os casos são os mesmos do Vitest (`front-lafiga/src/app/utils/estacaoDoMundo.bdd.test.ts`): a estação contínua tem de
# dar igual nos dois lados (a E1 de `jogo/composicao-do-mapa.md`).
RSpec.describe Mundo::Estacao do
  casos = JSON.parse(File.read(Rails.root.join('config/mundo/estacoes_casos.json')))

  describe '.estado' do
    casos['estados'].each do |c|
      it(c['nome']) do
        estado = described_class.estado(c['minuto'])
        esperado = c['esperado']

        expect(estado.except(:progresso, :mistura)).to eq(esperado.except('progresso', 'mistura').symbolize_keys)
        expect(estado[:progresso]).to be_within(1e-12).of(esperado['progresso'])
        expect(estado[:mistura]).to be_within(1e-12).of(esperado['mistura'])
      end
    end
  end

  it 'a mistura anda um passo por dia, sem salto, pelo ano inteiro' do
    misturas = (0...Mundo::Relogio::DIAS_NO_ANO).map { |dia| described_class.estado(dia * Mundo::Relogio::MINUTOS_NO_DIA) }
    misturas.each_cons(2) do |a, b|
      next if b[:passo_da_ponte].zero? || a[:passo_da_ponte].zero?

      expect(b[:passo_da_ponte] - a[:passo_da_ponte]).to eq(1)
    end
    expect(misturas.count { |e| e[:passo_da_ponte].positive? }).to eq(4 * described_class::DIAS_DA_PONTE)
  end
end
