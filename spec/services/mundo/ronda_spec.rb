# frozen_string_literal: true

require 'rails_helper'

# Uma ronda do processo `relogio` (L0.5): avança só os mundos com evento vencido, uma ronda por vez (a trava global),
# e aponta o evento que segura um mundo.
RSpec.describe Mundo::Ronda do
  let(:inicio) { Time.utc(2026, 10, 9, 12) }
  let(:agora) { inicio + 15.minutes } # 10 h de jogo depois do meio-dia

  def mundo!(**atributos)
    create(:mundo, epoca_em: inicio, minuto_na_epoca: 720, fator: 40, **atributos)
  end

  def marca(mundo, minuto, tipo: 'sino')
    Mundo::Agenda::Marca.call(mundo, minuto: minuto, tipo: tipo, chave: "#{tipo}:#{minuto}")
  end

  it 'avança só os mundos com evento vencido, cada um no seu minuto' do
    vencido = mundo!
    marca(vencido, 780)
    futuro = mundo!
    marca(futuro, 5000)
    pausado = mundo!(pausado_desde: inicio + 1.minute) # parou às 12h40
    marca(pausado, 780)

    r = described_class.call(agora: agora)

    expect(r.to_h).to include(rodou: true, mundos: 1, processados: 1, ocupados: 0, erros: [], parados: [])
    expect(vencido.eventos.pendentes).to be_empty
    expect(futuro.eventos.pendentes.count).to eq(1)
    expect(pausado.eventos.pendentes.count).to eq(1)
  end

  it 'com outra ronda em curso (a trava global), não roda' do
    mundo = mundo!
    marca(mundo, 780)
    com_outra_sessao_pg do |outra|
      outra.exec("SELECT pg_advisory_lock(#{described_class::TRAVA_GLOBAL})")
      expect(described_class.call(agora: agora).rodou).to be(false)
      expect(mundo.eventos.pendentes.count).to eq(1)
    end

    expect(described_class.call(agora: agora).processados).to eq(1)
  end

  it 'REGRESSAO: com o cache de consultas ligado, a trava global pergunta ao banco a cada ronda' do
    mundo = mundo!
    marca(mundo, 780)
    ActiveRecord::Base.cache do
      com_outra_sessao_pg do |outra|
        outra.exec("SELECT pg_advisory_lock(#{described_class::TRAVA_GLOBAL})")
        expect(described_class.call(agora: agora).rodou).to be(false)
      end

      expect(described_class.call(agora: agora).processados).to eq(1)
    end
  end

  it 'solta a trava global ao terminar, mesmo quando um mundo falha' do
    mundo = mundo!
    marca(mundo, 780, tipo: 'cometa')

    expect(described_class.call(agora: agora).erros).to match([[mundo.id, a_string_including('tipo de evento desconhecido')]])
    expect(described_class.call(agora: agora).rodou).to be(true)
  end

  it 'aponta o evento que segura o mundo depois de 3 falhas' do
    mundo = mundo!
    cometa = marca(mundo, 780, tipo: 'cometa')
    marca(mundo, 840)

    expect(described_class.call(agora: agora).parados).to eq([]) # 1ª falha
    expect(described_class.call(agora: agora).parados).to eq([]) # 2ª
    r = described_class.call(agora: agora)                       # 3ª

    expect(r.parados).to match([[mundo.id, cometa.id, 'cometa', 3, a_string_including('tipo de evento desconhecido')]])
    expect(mundo.eventos.find_by(minuto: 840).processado_em).to be_nil
  end
end
