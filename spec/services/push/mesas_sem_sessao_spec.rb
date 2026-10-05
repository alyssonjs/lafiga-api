# frozen_string_literal: true

require 'rails_helper'

# A MESA SEM SESSÃO MARCADA (05/10): quem recebe, quando, e quais datas a notificação oferece.
RSpec.describe Push::MesasSemSessao do
  let(:dm) { create(:user) }
  let(:jogador) { create(:user) }
  let(:outro_jogador) { create(:user) }
  let(:group) { create(:group, name: 'Batutinhas', dm_user_id: dm.id) }
  let(:hoje) { Date.new(2026, 10, 5) } # uma segunda-feira
  let(:agora) { Time.zone.local(2026, 10, 5, 10, 0) }

  before do
    allow(Push::Sender).to receive(:vapid_configured?).and_return(true)
    allow(Push::Sender).to receive(:call).and_return(1)
  end

  def com_push(user)
    PushSubscription.create!(user: user, endpoint: "https://push.example/#{user.id}", p256dh_key: 'k', auth_key: 'a')
    user.update!(notify_session_reminders: true)
    user
  end

  def na_mesa(user, nome)
    create(:character, user: user, name: nome, group_id: group.id)
  end

  def dia(data)
    DateDimension.find_by(date: data) || create(:date_dimension, date: data)
  end

  # sessão PASSADA concluída: não ocupa o slot, mas conta no histórico do dia da mesa
  def jogou_em!(data, hora = '21:00')
    s = create(:schedule, group: group, date_dimension: dia(data), status: :completed)
    s.update_columns(scheduled_time: hora)
    s
  end

  def aberta_em!(data)
    s = create(:schedule, group: group, date_dimension: dia(data), status: :completed)
    s.update_columns(status: Schedule.statuses.fetch('reserved'))
    s
  end

  subject(:resultado) { described_class.call(now: agora) }

  describe 'quem recebe' do
    before do
      na_mesa(com_push(jogador), 'Aberama')
      na_mesa(com_push(dm), 'PJ do Mestre')
      jogou_em!(hoje - 7)
    end

    it 'os JOGADORES da mesa — o Mestre fica de fora (a escolha da mesa)' do
      expect(Push::Sender).to receive(:call).with(hash_including(user: jogador)).once.and_return(1)
      expect(Push::Sender).not_to receive(:call).with(hash_including(user: dm))
      expect(resultado.avisadas).to eq(1)
    end

    it 'não avisa quem desligou o aviso, nem quem não tem aparelho' do
      jogador.update!(notify_session_reminders: false)
      na_mesa(outro_jogador, 'Sem push') # sem assinatura
      expect(Push::Sender).not_to receive(:call)
      expect(resultado.avisadas).to eq(0)
      expect(resultado.lines.join).to include('nenhum jogador com push')
    end
  end

  describe 'quando avisa' do
    before { na_mesa(com_push(jogador), 'Aberama') }

    it 'avisa a mesa sem sessão' do
      jogou_em!(hoje - 7)
      expect(resultado.avisadas).to eq(1)
    end

    it 'cala quando a mesa já tem a próxima marcada', :aggregate_failures do
      aberta_em!(hoje + 3)
      expect(resultado.avisadas).to eq(0)
      expect(resultado.lines.join).to include('já tem sessão marcada')
    end

    it 'cala por 3 dias depois de avisar, e volta no 4º', :aggregate_failures do
      jogou_em!(hoje - 7)
      expect(described_class.call(now: agora).avisadas).to eq(1)
      expect(group.reload.no_session_notified_at).to be_within(1.second).of(agora)

      expect(described_class.call(now: agora + 2.days).avisadas).to eq(0)
      expect(described_class.call(now: agora + 4.days).avisadas).to eq(1)
    end

    it 'cala na mesa sem jogador nenhum' do
      group.characters.destroy_all
      expect(resultado.avisadas).to eq(0)
      expect(resultado.lines.join).to include('sem jogador')
    end

    it 'DRY RUN: relata sem enviar nem marcar', :aggregate_failures do
      jogou_em!(hoje - 7)
      expect(Push::Sender).not_to receive(:call)
      r = described_class.call(now: agora, apply: false)
      expect(r.avisadas).to eq(1)
      expect(r.lines.join).to include('[avisaria]')
      expect(group.reload.no_session_notified_at).to be_nil
    end
  end

  describe 'as datas que oferece' do
    let(:servico) { described_class.new(now: agora) }

    before { na_mesa(com_push(jogador), 'Aberama') }

    it 'o DIA DA MESA sai do histórico: jogou 3 segundas → as próximas segundas', :aggregate_failures do
      [21, 14, 7].each { |n| jogou_em!(hoje - n) } # segundas
      expect(servico.dia_da_mesa(group)).to eq(1)
      expect(servico.datas_sugeridas(group)).to eq([Date.new(2026, 10, 12), Date.new(2026, 10, 19)])
      expect(servico.horario_da_mesa(group)).to eq('21:00')
    end

    it 'sem padrão (cada semana num dia), oferece os próximos dias' do
      jogou_em!(hoje - 7)  # segunda
      jogou_em!(hoje - 11) # quinta
      jogou_em!(hoje - 16) # sábado
      expect(servico.dia_da_mesa(group)).to be_nil
      expect(servico.datas_sugeridas(group)).to eq([hoje + 1, hoje + 2])
    end

    it 'pula o dia que o Mestre vetou no calendário' do
      [21, 14, 7].each { |n| jogou_em!(hoje - n) }
      dia(Date.new(2026, 10, 12)).update!(available: false)
      expect(servico.datas_sugeridas(group)).to eq([Date.new(2026, 10, 19), Date.new(2026, 10, 26)])
    end

    it 'a mesa nova (sem histórico) recebe os próximos dias' do
      expect(servico.dia_da_mesa(group)).to be_nil
      expect(servico.datas_sugeridas(group)).to eq([hoje + 1, hoje + 2])
    end
  end

  describe 'a sessão ATRASADA que ficou em aberto (os Peregrinos, 05/10)' do
    # sem encerrá-la a mesa não marca outra: o aviso pede para encerrar, em vez de oferecer datas
    let!(:travada) do
      na_mesa(com_push(jogador), 'Aberama')
      s = aberta_em!(hoje - 14)
      s.update_columns(status: Schedule.statuses.fetch('in_progress'), title: 'Os demogorgon chegaram')
      s.reload
    end

    it 'avisa para encerrar a antiga, com o botão abrindo ela', :aggregate_failures do
      enviado = nil
      allow(Push::Sender).to receive(:call) { |kw| enviado = kw; 1 }

      expect(resultado.avisadas).to eq(1)
      expect(enviado[:title]).to eq('Batutinhas está sem a próxima sessão marcada')
      expect(enviado[:body]).to eq("A sessão de #{(hoje - 14).strftime('%d/%m')} (Os demogorgon chegaram) ficou em aberto. Encerrem ela para marcar a próxima.")
      expect(enviado[:actions]).to eq([{ action: "/sessions/api-#{travada.id}", title: 'Abrir a sessão' }])
      expect(enviado[:url]).to eq("/sessions/api-#{travada.id}")
    end

    it 'encerrada a antiga, o aviso volta a ser o das datas' do
      travada.update_columns(status: Schedule.statuses.fetch('completed'))
      enviado = nil
      allow(Push::Sender).to receive(:call) { |kw| enviado = kw; 1 }

      expect(resultado.avisadas).to eq(1)
      expect(enviado[:actions].first[:action]).to start_with('/sessions?nova=')
    end
  end

  describe 'a notificação' do
    before do
      na_mesa(com_push(jogador), 'Aberama')
      [21, 14, 7].each { |n| jogou_em!(hoje - n) }
    end

    it 'leva as datas como BOTÕES, e cada botão abre a criação naquele dia', :aggregate_failures do
      enviado = nil
      allow(Push::Sender).to receive(:call) { |kw| enviado = kw; 1 }

      resultado

      expect(enviado[:title]).to eq('Batutinhas está sem sessão marcada')
      expect(enviado[:body]).to eq('Vocês costumam jogar segunda: seg, 12/10 ou seg, 19/10 às 21:00?')
      expect(enviado[:actions]).to eq([
        { action: '/sessions?nova=2026-10-12&hora=21:00', title: 'seg, 12/10' },
        { action: '/sessions?nova=2026-10-19&hora=21:00', title: 'seg, 19/10' },
      ])
      # o iPhone não desenha botão: a `url` leva ao mesmo lugar do primeiro
      expect(enviado[:url]).to eq('/sessions?nova=2026-10-12&hora=21:00')
      expect(enviado[:tag]).to eq("sem-sessao-#{group.id}")
    end
  end
end
