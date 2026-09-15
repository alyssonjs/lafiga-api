# frozen_string_literal: true

require 'rails_helper'

# Lembretes de sessão (Web Push). Até 15/09/2026 a rake nunca rodou em prod — o cron
# redirecionava para /var/log, sem permissão — e não havia um teste sequer.
RSpec.describe Push::SessionReminders do
  let(:hoje) { Date.new(2031, 3, 10) }
  let(:dia) { DateDimension.find_by(date: hoje) || create(:date_dimension, date: hoje) }
  let(:mestre) { create(:user) }
  let(:jogador) { create(:user) }
  let(:grupo) { create(:group, name: 'Batutinhas', dm_user_id: mestre.id) }
  let!(:sessao) do
    create(:schedule, group: grupo, date_dimension: dia, title: 'Covil', status: :waiting, scheduled_time: '21:00')
  end
  let(:enviados) { [] }

  def as(hora, minuto = 0)
    Time.zone.local(hoje.year, hoje.month, hoje.day, hora, minuto)
  end

  def inscrever(user)
    PushSubscription.create!(user: user, endpoint: "https://push.test/#{user.id}/#{SecureRandom.hex(4)}",
                             p256dh_key: 'p256dh', auth_key: 'auth')
  end

  def participar(user, nome, schedule: sessao)
    ScheduleCharacter.create!(schedule: schedule, character: create(:character, user: user, name: nome))
  end

  def titulos_para(user)
    enviados.select { |envio| envio[:user] == user }.map { |envio| envio[:title] }
  end

  before do
    participar(jogador, 'Aberama')
    inscrever(jogador)
    inscrever(mestre)
    allow(Push::Sender).to receive(:vapid_configured?).and_return(true)
    allow(Push::Sender).to receive(:call) do |**envio|
      enviados << envio
      1
    end
  end

  it 'antes das 8h não manda nada' do
    described_class.call(now: as(7, 50))

    expect(enviados).to be_empty
    expect(sessao.reload.reminders_sent).to eq({})
  end

  it 'a partir das 8h manda "Sessão hoje" UMA vez, ao jogador e ao Mestre do grupo' do
    described_class.call(now: as(8, 5))
    described_class.call(now: as(8, 20))

    expect(titulos_para(jogador)).to eq(['Sessão hoje: Covil'])
    expect(titulos_para(mestre)).to eq(['Sessão hoje: Covil'])
    expect(enviados.find { |envio| envio[:user] == jogador }[:body]).to eq('Aberama · Batutinhas · às 21:00')
    expect(sessao.reload.reminders_sent).to eq('day' => hoje.iso8601)
  end

  it 'faltando até 1h manda "Começa em breve" uma vez' do
    described_class.call(now: as(8))
    described_class.call(now: as(20, 5))
    described_class.call(now: as(20, 20))

    expect(titulos_para(jogador)).to eq(['Sessão hoje: Covil', 'Começa em breve: Covil'])
    expect(sessao.reload.reminders_sent).to eq('day' => hoje.iso8601, 'hour' => hoje.iso8601)
  end

  it 'não manda o de 1h antes da janela nem depois do início' do
    described_class.call(now: as(19, 55))
    described_class.call(now: as(21, 5))

    expect(titulos_para(jogador)).to eq(['Sessão hoje: Covil'])
    expect(sessao.reload.reminders_sent).not_to have_key('hour')
  end

  it 'ignora sessão cancelada e sessão de outro dia' do
    sessao.update_column(:status, Schedule.statuses[:cancelled])
    amanha = DateDimension.find_by(date: hoje + 1) || create(:date_dimension, date: hoje + 1)
    outra = create(:schedule, date_dimension: amanha, title: 'Amanhã', status: :waiting, scheduled_time: '20:30')
    participar(jogador, 'Aberama', schedule: outra)

    described_class.call(now: as(20, 0))

    expect(enviados).to be_empty
  end

  it 'ignora sessão de teste (sandbox)' do
    sessao.update_column(:sandbox, true)

    described_class.call(now: as(20, 30))

    expect(enviados).to be_empty
  end

  it 'só avisa quem tem opt-in e ao menos um aparelho inscrito' do
    sem_aparelho = create(:user)
    desligou = create(:user, notify_session_reminders: false)
    participar(sem_aparelho, 'Sabrino')
    participar(desligou, 'Nykos')
    inscrever(desligou)

    described_class.call(now: as(9))

    expect(enviados.map { |envio| envio[:user] }).to contain_exactly(jogador, mestre)
  end

  it 'avisa também quem criou a sessão' do
    criador = create(:user)
    inscrever(criador)
    sessao.update_column(:created_by_user_id, criador.id)

    described_class.call(now: as(9))

    expect(titulos_para(criador)).to eq(['Sessão hoje: Covil'])
  end

  it 'sem VAPID configurado não envia nem marca' do
    allow(Push::Sender).to receive(:vapid_configured?).and_return(false)

    described_class.call(now: as(9))

    expect(enviados).to be_empty
    expect(sessao.reload.reminders_sent).to eq({})
  end
end
