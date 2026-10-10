# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# O laço do processo `relogio` (L0.5): a ronda a cada 15 s, a pista rápida a cada 5 s, sem cair quando uma ronda falha,
# e parando no sinal.
RSpec.describe ProcessoRelogio do
  let(:saida) { StringIO.new }
  let(:sonos) { [] }
  let(:agora) { Time.utc(2026, 10, 9, 12, 15) }
  let(:processo) { described_class.new(saida: saida, dorme: ->(s) { sonos << s }, agora: -> { agora }) }

  def vazio
    Mundo::Ronda::Resultado.new(rodou: true, mundos: 0, processados: 0, ocupados: 0, erros: [], parados: [])
  end

  it 'faz uma ronda a cada 3 tiques de 5 s, e a pista rápida a cada tique' do
    allow(Mundo::Ronda).to receive(:call).and_return(vazio)
    allow(processo).to receive(:pista_rapida).and_call_original

    processo.rodar(max_tiques: 6)

    expect(Mundo::Ronda).to have_received(:call).with(agora: agora).twice
    expect(processo).to have_received(:pista_rapida).exactly(6).times
    expect(sonos).to eq([5] * 5)
  end

  it 'uma ronda que falha não derruba o laço' do
    chamadas = 0
    allow(Mundo::Ronda).to receive(:call) do
      chamadas += 1
      raise PG::ConnectionBad, 'o banco caiu' if chamadas == 1

      vazio
    end

    processo.rodar(max_tiques: 4)

    expect(chamadas).to eq(2)
    expect(saida.string).to include('a ronda falhou: PG::ConnectionBad: o banco caiu')
  end

  it 'para no sinal, ao fim do tique em curso' do
    allow(Mundo::Ronda).to receive(:call).and_return(vazio)
    para = described_class.new(saida: saida, dorme: ->(_) { para.parar! }, agora: -> { agora })

    para.rodar

    expect(Mundo::Ronda).to have_received(:call).once
  end

  it 'avisa uma vez o evento que segura um mundo, e de novo se ele voltar a segurar' do
    parado = vazio.dup.tap { |r| r.parados = [[7, 42, 'cometa', 3, 'ArgumentError: tipo de evento desconhecido']] }
    allow(Mundo::Ronda).to receive(:call).and_return(parado, parado, vazio, parado)

    4.times { processo.ronda }

    expect(saida.string.scan('o evento 42 (cometa) segura o mundo 7').size).to eq(2)
  end

  it 'conta o que a ronda fez, e cala quando não houve nada' do
    cheio = vazio.dup.tap { |r| r.mundos = 2; r.processados = 5 }
    allow(Mundo::Ronda).to receive(:call).and_return(vazio, cheio)

    2.times { processo.ronda }

    expect(saida.string.lines).to eq(["[relogio] 2 mundo(s), 5 evento(s)\n"])
  end

  describe 'a tarefa mundo:ronda' do
    before do
      Rake::Task.clear
      Rails.application.load_tasks
    end

    it 'roda uma ronda e processa o que venceu' do
      mundo = create(:mundo, epoca_em: 1.hour.ago, minuto_na_epoca: 0, fator: 40)
      Mundo::Agenda::Marca.call(mundo, minuto: 60, tipo: 'sino', chave: 'sino:60')

      expect { Rake::Task['mundo:ronda'].invoke }.to output(/1 mundo\(s\), 1 evento\(s\)/).to_stdout
      expect(mundo.eventos.pendentes).to be_empty
    end
  end
end
