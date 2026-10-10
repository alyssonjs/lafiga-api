# frozen_string_literal: true

require 'rails_helper'

# Os eventos sistêmicos (L0.7; plano I7, GDD §116). O roteiro do roadmap: fatores conhecidos → a chance esperada;
# fonte fixa → o mesmo resultado. O exemplo é a doença.
RSpec.describe Mundo::Eventos do
  include ActiveSupport::Testing::TimeHelpers

  it 'o catálogo carrega, só com inteiros, e tem a doença' do
    doenca = described_class.catalogo['doenca']

    expect(doenca).to include('nome' => 'Doença', 'base' => 5, 'piso' => 1, 'teto' => 95)
    expect(doenca['fatores'].keys).to match_array(%w[populacao_alta agua_contaminada estacao_umida pantano curandeiro poco hospital])
  end

  describe 'fatores conhecidos → a chance esperada (a doença)' do
    {
      [] => 5,
      %w[populacao_alta agua_contaminada] => 30,
      %w[populacao_alta agua_contaminada estacao_umida pantano] => 45,
      %w[populacao_alta agua_contaminada estacao_umida pantano poco curandeiro] => 25,
      %w[curandeiro poco hospital] => 1, # o piso: sempre há risco
    }.each do |ativos, esperada|
      it("#{ativos.empty? ? 'sem fator' : ativos.join(' + ')} → #{esperada}%") do
        expect(described_class.chance(:doenca, ativos: ativos)['chance']).to eq(esperada)
      end
    end

    it 'um fator pode valer mais de uma vez' do
      c = described_class.chance('doenca', ativos: { 'populacao_alta' => 3, 'poco' => 1 })

      expect(c['chance']).to eq(5 + 30 - 10)
      expect(c['fatores'].map { |f| f.values_at('chave', 'soma') }).to eq([['poco', -10], ['populacao_alta', 30]])
    end

    it 'o teto segura a chance' do
      expect(described_class.chance(:doenca, ativos: { 'agua_contaminada' => 10 })['chance']).to eq(95)
    end

    it 'recusa o evento e o fator que não existem' do
      expect { described_class.chance(:meteoro, ativos: []) }.to raise_error(ArgumentError)
      expect { described_class.chance(:doenca, ativos: %w[peste_negra]) }.to raise_error(ArgumentError)
    end
  end

  describe 'fonte fixa → o mesmo resultado' do
    it 'a mesma chave rola o mesmo evento, e a rolagem guarda os fatores' do
      a = described_class.rola(:doenca, ativos: %w[pantano poco], chave: 'mundo:9:doenca:1')
      b = described_class.rola(:doenca, ativos: %w[pantano poco], chave: 'mundo:9:doenca:1')

      expect(b).to eq(a)
      expect(a).to include('evento' => 'doenca', 'chance' => 5)
      expect(a['acontece']).to eq(a['rolado'] <= 5)
      rolagem = Dados::Rolagem.find(a['rolagem'])
      expect(rolagem.detalhe['fatores'].map { |f| f['chave'] }).to eq(%w[pantano poco])
      expect(rolagem.contexto).to include('evento' => 'doenca')
    end
  end

  describe 'pela agenda do mundo' do
    it 'o evento sistêmico rola no seu minuto, e reprocessar devolve a mesma rolagem' do
      inicio = Time.utc(2026, 10, 9, 12)
      mundo = create(:mundo, epoca_em: inicio, minuto_na_epoca: 720, fator: 40)
      Mundo::Agenda::Marca.call(mundo, minuto: 780, tipo: 'sistemico', chave: 'doenca:dia-1',
                                       dados: { 'evento' => 'doenca', 'fatores' => %w[populacao_alta agua_contaminada] })

      travel_to(inicio + 5.minutes) { Mundo::Avanca.call(mundo, agora: Time.current) }

      resultado = mundo.eventos.find_by!(chave: 'doenca:dia-1').resultado
      expect(resultado).to include('evento' => 'doenca', 'chance' => 30)
      rolagem = Dados::Rolagem.find(resultado['rolagem'])
      expect(rolagem.chave).to eq("mundo:#{mundo.id}:agenda:doenca:dia-1")
      expect(Mundo::Agenda::Sistemico.call(mundo.eventos.find_by!(chave: 'doenca:dia-1'), nil)).to eq(resultado)
    end
  end
end
