# frozen_string_literal: true

module Push
  # Lembretes Web Push das sessões de HOJE. Quem chama é a rake
  # `push:session_reminders`, disparada pelo cron do servidor a cada 15 min
  # (deploy/crontab). Os avisos de EVENTO (criada/cancelada) são outro caminho:
  # Push::SessionNotifier via SessionPushJob.
  #
  # Dois lembretes por sessão/dia, idempotentes via `schedules.reminders_sent`:
  #   - "day"  : a partir das 8h, uma vez — "Sessão hoje".
  #   - "hour" : quando faltam até 60 min para o `scheduled_time` — "Começa em breve".
  # Destinatários: participantes (characters -> user) + quem criou + o Mestre do
  # grupo — os mesmos do SessionNotifier. Só quem tem opt-in E ao menos uma assinatura.
  #
  # ⚠️ Até 15/09/2026 isto nunca rodou em prod: o cron redirecionava a saída para
  # /var/log, onde o usuário deploy não grava, e o shell nem executava a rake.
  class SessionReminders
    MORNING_HOUR = 8
    HOUR_WINDOW = 60.minutes

    Result = Struct.new(:counts, :lines, :sessions, keyword_init: true)

    def self.call(now: Time.zone.now)
      new(now: now).call
    end

    def initialize(now:)
      @now = now
      @today = now.to_date
      @today_s = @today.iso8601
    end

    # @return [Result] sessões lembradas por tipo, linhas de log e total de sessões de hoje
    def call
      counts = Hash.new(0)
      lines = []
      return Result.new(counts: counts, lines: lines, sessions: 0) unless Push::Sender.vapid_configured?

      scope = schedules_today
      scope.find_each do |sched|
        sent = sched.reminders_sent.is_a?(Hash) ? sched.reminders_sent.dup : {}
        due = due_reminders(sched, sent)
        next if due.empty?

        ids = recipient_user_ids(sched)
        next if ids.empty?

        users = User.where(id: ids, notify_session_reminders: true)
                    .where(id: PushSubscription.select(:user_id))
        chars = character_names_by_user(sched)
        tail = [sched.group&.name.presence, time_label(sched)]

        due.each do |type, title|
          delivered = 0
          users.find_each do |user|
            # jogador: "Aberama Gold · Batutinhas · às 19:00" | Mestre: "Batutinhas · às 19:00"
            body = [chars[user.id].presence, *tail].compact.join(' · ')
            delivered += Push::Sender.call(user: user, title: title, body: body,
                                           url: "/sessions/api-#{sched.id}", tag: "session-#{sched.id}-#{type}")
          end
          sent[type] = @today_s
          counts[type] += 1
          lines << "[#{type}] schedule ##{sched.id} '#{sched.title}' → #{users.count} user(s), #{delivered} device(s)"
        end

        sched.update_column(:reminders_sent, sent)
      end

      Result.new(counts: counts, lines: lines, sessions: scope.count)
    end

    private

    def schedules_today
      Schedule.where(status: %i[reserved waiting], sandbox: false)
              .joins(:date_dimension)
              .where(date_dimensions: { date: @today })
              .includes(:group, characters: :user)
    end

    def due_reminders(sched, sent)
      due = []
      due << ['day', "Sessão hoje: #{sched.title}"] if @now.hour >= MORNING_HOUR && sent['day'] != @today_s

      start_at = start_time(sched)
      if start_at && sent['hour'] != @today_s && start_at > @now && (start_at - @now) <= HOUR_WINDOW
        due << ['hour', "Começa em breve: #{sched.title}"]
      end
      due
    end

    # Início no fuso do app a partir de scheduled_time ("21:00").
    def start_time(sched)
      return nil if sched.scheduled_time.to_s.strip.empty?

      Time.zone.parse("#{@today_s} #{sched.scheduled_time}")
    rescue ArgumentError
      nil
    end

    def time_label(sched)
      sched.scheduled_time.present? ? "às #{sched.scheduled_time}" : nil
    end

    # user_id => nome do 1º personagem dele nesta sessão (o Mestre, sem PC, fica de fora).
    def character_names_by_user(sched)
      sched.characters.each_with_object({}) do |character, map|
        map[character.user_id] ||= character.name if character.user_id.present?
      end
    end

    # Participantes + quem criou + Mestre do grupo, sem repetir.
    def recipient_user_ids(sched)
      ids = sched.characters.map(&:user_id)
      ids << sched.created_by_user_id
      ids << sched.group&.dm_user_id
      ids.compact.uniq
    end
  end
end
