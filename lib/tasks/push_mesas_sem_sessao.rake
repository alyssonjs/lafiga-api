# frozen_string_literal: true

# A MESA SEM SESSÃO MARCADA (05/10) — avisa os jogadores por Web Push, com as próximas datas do dia da mesa como
# botões. Agendada uma vez por dia pelo cron do servidor; a linha mora VERSIONADA em deploy/crontab.
#
#   bin/rails push:mesas_sem_sessao              # envia (e marca o grupo como avisado)
#   DRY_RUN=1 bin/rails push:mesas_sem_sessao    # só relata: não envia nem marca
#
# A regra (janela, repetição, datas, destinatários) está em Push::MesasSemSessao.
namespace :push do
  desc 'Avisa os jogadores das mesas sem sessão marcada nas próximas 2 semanas. DRY_RUN=1 só relata.'
  task mesas_sem_sessao: :environment do
    seco = ENV['DRY_RUN'].to_s == '1'
    if !seco && !Push::Sender.vapid_configured?
      warn '[push:mesas_sem_sessao] VAPID não configurado — abortando.'
      next
    end

    puts '== DRY RUN (não envia nem marca) ==' if seco
    resultado = Push::MesasSemSessao.call(apply: !seco)
    resultado.lines.each { |line| puts line }
    puts "== push:mesas_sem_sessao #{Time.zone.now.strftime('%d/%m %H:%M')} == " \
         "#{resultado.avisadas} mesa(s) #{seco ? 'a avisar' : 'avisada(s)'} de #{resultado.grupos} olhada(s)"
  end
end
