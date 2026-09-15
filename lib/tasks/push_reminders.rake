# frozen_string_literal: true

# Lembretes de sessão via Web Push. Agendado pelo cron do servidor a cada 15 min —
# a linha mora VERSIONADA em deploy/crontab (instalada pelo server-deploy.sh).
# A regra (janelas, idempotência, destinatários) está em Push::SessionReminders.
namespace :push do
  desc 'Envia lembretes Web Push das sessões de hoje (participantes + Mestre).'
  task session_reminders: :environment do
    unless Push::Sender.vapid_configured?
      warn '[push:session_reminders] VAPID não configurado — abortando.'
      next
    end

    result = Push::SessionReminders.call
    result.lines.each { |line| puts line }
    puts "== push:session_reminders #{Time.zone.now.strftime('%d/%m %H:%M')} == " \
         "#{result.counts.sort.to_h.inspect} (#{result.sessions} sessão(ões) hoje)"
  end
end
