# frozen_string_literal: true

require 'rails_helper'

# O avanço do mundo (L0.4; plano B1). O roteiro do roadmap: com `travel_to`, o mundo alcança 10 h em ordem;
# reprocessar não duplica; depois de uma falha, o resultado final é o mesmo de um avanço sem falha.
RSpec.describe Mundo::Avanca do
  include ActiveSupport::Testing::TimeHelpers

  # o meio-dia do dia 1, no fator 40: 15 min reais são 10 h de jogo
  let(:inicio) { Time.utc(2026, 10, 9, 12) }

  # o sino toca a cada hora, das 13h às 23h
  def mundo_com_sino!
    mundo = create(:mundo, epoca_em: inicio, minuto_na_epoca: 720, fator: 40)
    Mundo::Agenda::Marca.call(mundo, minuto: 780, tipo: 'sino', chave: 'sino:780', dados: { 'a_cada' => 60, 'ate' => 1380 })
    mundo
  end

  def avanca(mundo, depois: 15.minutes, **opcoes)
    travel_to(inicio + depois) { described_class.call(mundo, agora: Time.current, **opcoes) }
  end

  def toques(mundo)
    mundo.eventos.where(tipo: 'sino').order(:minuto).map { |e| [e.minuto, e.resultado] }
  end

  it 'alcança 10 h em ordem, cada evento no seu minuto' do
    mundo = mundo_com_sino!
    ordem = []
    allow(Mundo::Agenda::Sino).to receive(:call).and_wrap_original do |original, evento, momento|
      ordem << evento.minuto
      original.call(evento, momento)
    end

    expect(avanca(mundo).to_h).to include(processados: 10, em_dia: true, ocupado: false, erro: nil)
    expect(ordem).to eq((780..1320).step(60).to_a)
    # o das 23h já está marcado, mas ainda não venceu
    expect(mundo.eventos.pendentes.pluck(:minuto)).to eq([1380])
    # o minuto do evento é o agora do handler: o das 22h diz 22h, não a hora em que o avanço rodou
    expect(mundo.eventos.find_by(minuto: 1320).resultado).to eq('hora' => 22, 'dia' => 0, 'criador' => 'Ilahim')
    expect(mundo.eventos.find_by(minuto: 1320).processado_em).to eq(inicio + 15.minutes)
  end

  it 'reprocessar não duplica: nem o avanço, nem a marca' do
    mundo = mundo_com_sino!
    avanca(mundo)
    antes = toques(mundo)

    expect(avanca(mundo).processados).to eq(0)
    Mundo::Agenda::Marca.call(mundo, minuto: 780, tipo: 'sino', chave: 'sino:780', dados: { 'a_cada' => 60 })
    expect(toques(mundo)).to eq(antes)
    expect(mundo.eventos.count).to eq(11)
  end

  it 'depois de uma falha no meio, chega ao mesmo resultado de um avanço sem falha' do
    limpo = mundo_com_sino!
    avanca(limpo)

    com_falha = mundo_com_sino!
    falhou = false
    allow(Mundo::Agenda::Sino).to receive(:call).and_wrap_original do |original, evento, momento|
      if evento.mundo_id == com_falha.id && evento.minuto == 1020 && !falhou
        falhou = true
        raise 'a corda do sino partiu'
      end
      original.call(evento, momento)
    end

    r = avanca(com_falha)
    expect(r.to_h).to include(processados: 4, em_dia: false, ocupado: false)
    expect(r.erro).to include('a corda do sino partiu')
    # o evento que falhou continua pendente, com a falha anotada, e o que ele marcaria não existe: a transação dele foi
    # desfeita inteira
    falho = com_falha.eventos.find_by(minuto: 1020)
    expect(falho.processado_em).to be_nil
    expect(falho.tentativas).to eq(1)
    expect(falho.erro).to include('a corda do sino partiu')
    expect(com_falha.eventos.where(minuto: 1080)).to be_empty

    expect(avanca(com_falha).to_h).to include(processados: 6, em_dia: true)
    expect(toques(com_falha)).to eq(toques(limpo))
    expect(com_falha.eventos.find_by(minuto: 1020).erro).to be_nil
  end

  it 'com o mundo nas mãos de outro avanço, sai ocupado sem esperar' do
    mundo = mundo_com_sino!
    com_outra_sessao_pg do |outra|
      outra.exec("SELECT pg_advisory_lock(#{described_class::TRAVA}, #{mundo.id})")
      expect(avanca(mundo).to_h).to include(processados: 0, ocupado: true, em_dia: false)
    end

    expect(avanca(mundo).processados).to eq(10)
  end

  it 'REGRESSAO: com o cache de consultas ligado (o executor do relogio), a trava pergunta ao banco a cada vez' do
    mundo = mundo_com_sino!
    ActiveRecord::Base.cache do
      com_outra_sessao_pg do |outra|
        outra.exec("SELECT pg_advisory_lock(#{described_class::TRAVA}, #{mundo.id})")
        expect(avanca(mundo).ocupado).to be(true)
      end

      expect(avanca(mundo).processados).to eq(10)
    end
  end

  it 'para no limite de eventos e diz que não ficou em dia' do
    mundo = mundo_com_sino!

    expect(avanca(mundo, limite: 3).to_h).to include(processados: 3, em_dia: false)
    expect(avanca(mundo, limite: 100).to_h).to include(processados: 7, em_dia: true)
  end

  it 'um tipo desconhecido anota a falha e segura o mundo ali' do
    mundo = create(:mundo, epoca_em: inicio, minuto_na_epoca: 720, fator: 40)
    Mundo::Agenda::Marca.call(mundo, minuto: 730, tipo: 'cometa', chave: 'cometa')
    Mundo::Agenda::Marca.call(mundo, minuto: 740, tipo: 'sino', chave: 'sino:740')

    r = avanca(mundo, depois: 1.minute)
    expect(r.to_h).to include(processados: 0, em_dia: false)
    expect(r.erro).to include('tipo de evento desconhecido')
    expect(mundo.eventos.find_by(chave: 'sino:740').processado_em).to be_nil
  end

  it 'com o relógio pausado, nada vence depois da pausa' do
    mundo = mundo_com_sino!
    mundo.reancora!(agora: inicio + 3.minutes, pausar: true)

    expect(avanca(mundo, depois: 2.hours).processados).to eq(2)
  end
end
