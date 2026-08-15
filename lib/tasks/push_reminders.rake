# frozen_string_literal: true

# Lembretes de sessão via Web Push. Rodar de tempos em tempos (cron do host, ~15min):
#   docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env.production \
#     exec -T web bin/rails push:session_reminders
#
# Dois lembretes por sessão/dia (idempotentes via schedules.reminders_sent):
#   - "day"  : de manhã (>= 8h), uma vez — "Você tem sessão hoje".
#   - "hour" : quando faltam <= ~60min p/ o scheduled_time — "Começa em breve".
# Destinatários: participantes (characters -> user) + Mestre (created_by_user). Só quem
# tem opt-in (notify_session_reminders) E ao menos uma assinatura.
namespace :push do
  desc 'Envia lembretes Web Push das sessões de hoje (participantes + Mestre).'
  task session_reminders: :environment do
    unless Push::Sender.vapid_configured?
      warn '[push:session_reminders] VAPID não configurado — abortando.'
      next
    end

    now      = Time.zone.now
    today    = now.to_date
    today_s  = today.iso8601
    morning  = now.hour >= 8            # não notificar "do dia" de madrugada
    counts   = Hash.new(0)

    schedules = Schedule
                .where(status: %i[reserved waiting], sandbox: false)
                .joins(:date_dimension)
                .where(date_dimensions: { date: today })
                .includes(:group, :created_by_user, characters: :user)

    schedules.find_each do |sched|
      sent = sched.reminders_sent.is_a?(Hash) ? sched.reminders_sent.dup : {}

      jobs = [] # [tipo, title, body]

      # (a) lembrete "do dia"
      if morning && sent['day'] != today_s
        jobs << ['day',
                 "Sessão hoje — #{sched.title}",
                 [("às #{sched.scheduled_time}" if sched.scheduled_time.present?),
                  sched.group&.name].compact.join(' · ').presence || 'Você tem sessão hoje']
      end

      # (b) lembrete "começa em breve" (<= ~60min, ainda no futuro)
      start_at = parse_start(today, sched.scheduled_time)
      if start_at && sent['hour'] != today_s && start_at > now && (start_at - now) <= 60.minutes
        jobs << ['hour',
                 'Sua sessão começa em breve',
                 "#{sched.title}#{" · às #{sched.scheduled_time}" if sched.scheduled_time.present?}"]
      end

      next if jobs.empty?

      user_ids = recipients_for(sched)
      next if user_ids.empty?

      users = User.where(id: user_ids, notify_session_reminders: true)
                  .where(id: PushSubscription.select(:user_id))

      jobs.each do |type, title, body|
        delivered = 0
        users.find_each do |u|
          delivered += Push::Sender.call(user: u, title: title, body: body, url: "/sessions/api-#{sched.id}", tag: "session-#{sched.id}-#{type}")
        end
        sent[type] = today_s
        counts[type] += 1
        puts "[#{type}] schedule ##{sched.id} '#{sched.title}' → #{users.count} user(s), #{delivered} device(s)"
      end

      sched.update_column(:reminders_sent, sent)
    end

    puts "== push:session_reminders == #{counts.sort.to_h.inspect} (#{schedules.count} sessão(ões) hoje)"
  end
end

# Monta o horário de início no fuso do app a partir de scheduled_time ("21:00").
def parse_start(date, scheduled_time)
  return nil if scheduled_time.to_s.strip.empty?

  Time.zone.parse("#{date.iso8601} #{scheduled_time}")
rescue ArgumentError
  nil
end

# user_ids = participantes (characters -> user) + Mestre (created_by_user), dedup.
def recipients_for(sched)
  ids = sched.characters.map(&:user_id)
  ids << sched.created_by_user_id
  ids.compact.uniq
end
