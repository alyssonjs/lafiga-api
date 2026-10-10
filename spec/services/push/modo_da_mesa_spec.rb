# frozen_string_literal: true

require 'rails_helper'

# Os pushes de sessão só olham a mesa de CAMPANHA (L0.8): a mesa da vila convive com ela sem disparar push e sem contar
# como "o próximo encontro marcado".
RSpec.describe 'pushes e o modo da mesa' do
  let(:mestre) { create(:user) }
  let(:jogador) { create(:user) }
  let(:group) { create(:group, name: 'Batutinhas', dm_user_id: mestre.id) }
  let(:enviados) { [] }

  def dia(data)
    DateDimension.find_by(date: data) || create(:date_dimension, date: data)
  end

  before do
    PushSubscription.create!(user: jogador, endpoint: "https://push.test/#{jogador.id}", p256dh_key: 'k', auth_key: 'a')
    jogador.update!(notify_session_reminders: true) if jogador.respond_to?(:notify_session_reminders)
    allow(Push::Sender).to receive(:vapid_configured?).and_return(true)
    allow(Push::Sender).to receive(:call) do |**envio|
      enviados << envio
      1
    end
  end

  describe Push::SessionReminders do
    let(:hoje) { Date.new(2031, 3, 10) }
    let(:oito_e_cinco) { Time.zone.local(2031, 3, 10, 8, 5) }

    it 'a mesa da vila de hoje não manda "Sessão hoje"; a de campanha manda' do
      vila = create(:schedule, group: group, date_dimension: dia(hoje), status: :waiting, title: 'Vila', modo: 'vila')
      ScheduleCharacter.create!(schedule: vila, character: create(:character, user: jogador, group: group))

      described_class.call(now: oito_e_cinco)
      expect(enviados).to be_empty
      expect(vila.reload.reminders_sent).to eq({})

      campanha = create(:schedule, group: group, date_dimension: dia(hoje), status: :waiting, title: 'Covil')
      ScheduleCharacter.create!(schedule: campanha, character: create(:character, user: jogador, group: group))
      described_class.call(now: oito_e_cinco)
      expect(enviados.map { |e| e[:title] }.uniq).to eq(['Sessão hoje: Covil'])
    end
  end

  describe Push::MesasSemSessao do
    let(:agora) { Time.zone.local(2026, 10, 5, 10, 0) }

    before do
      create(:character, user: jogador, name: 'Aberama', group_id: group.id)
      jogou = create(:schedule, group: group, date_dimension: dia(Date.new(2026, 9, 28)), status: :completed)
      jogou.update_columns(scheduled_time: '21:00')
    end

    it 'a mesa da vila marcada não conta como o próximo encontro: o grupo continua sem sessão' do
      create(:schedule, group: group, date_dimension: dia(Date.new(2026, 10, 8)), status: :waiting, modo: 'vila')

      expect(described_class.call(now: agora).avisadas).to eq(1)
    end

    it 'a sessão de campanha marcada conta' do
      create(:schedule, group: group, date_dimension: dia(Date.new(2026, 10, 8)), status: :waiting)

      expect(described_class.call(now: agora).avisadas).to eq(0)
    end
  end

  describe Push::SessionNotifier do
    it 'a mesa da vila não avisa como sessão' do
      vila = create(:schedule, group: group, date_dimension: dia(Date.new(2031, 3, 11)), status: :waiting, modo: 'vila')

      expect(described_class.new(schedule: vila, event: described_class::EVENTS.first).call).to eq(0)
      expect(enviados).to be_empty
    end
  end
end
