# frozen_string_literal: true

module Push
  # Notificações Web Push por EVENTO de sessão (criação / cancelamento).
  # Diferente do lembrete diário (lib/tasks/push_reminders.rake): dispara na hora,
  # via SessionPushJob (fora do request, porque o Push::Sender é síncrono).
  # Reaproveita o opt-in `notify_session_reminders` e só envia p/ quem tem
  # assinatura.
  #
  # Destinatários: participantes (schedule_characters -> user) + o Mestre da mesa
  # (group.dm_user). Quem disparou a ação NÃO recebe — exceto o Mestre, que deve
  # receber sempre (regra do produto).
  class SessionNotifier
    EVENTS = %w[created cancelled].freeze

    def self.call(schedule:, event:, actor_id: nil)
      new(schedule: schedule, event: event, actor_id: actor_id).call
    end

    def initialize(schedule:, event:, actor_id: nil)
      @schedule = schedule
      @event = event.to_s
      @actor_id = actor_id
    end

    # @return [Integer] devices que receberam
    def call
      return 0 unless EVENTS.include?(@event)
      return 0 if @schedule.nil?
      return 0 if @schedule.respond_to?(:sandbox?) && @schedule.sandbox?
      return 0 unless Push::Sender.vapid_configured?

      title = title_for(@event)
      tag   = "session-#{@schedule.id}-#{@event}"
      chars = character_names_by_user

      delivered = 0
      recipients.find_each do |user|
        who  = chars[user.id].presence # personagem do jogador; nil p/ o Mestre
        body = body_for(@event, who)
        delivered += Push::Sender.call(user: user, title: title, body: body, url: session_url, tag: tag)
      end
      delivered
    end

    private

    def title_for(event)
      case event
      when 'created'   then "Nova sessão marcada: #{@schedule.title}"
      when 'cancelled' then "Sessão cancelada: #{@schedule.title}"
      end
    end

    # created:   "Aberama Gold · Tripulação do Gold · 16/08 às 19:00"
    # cancelled: "Aberama Gold · Tripulação do Gold · 16/08"
    # (Mestre, sem personagem, cai só em grupo + data.)
    def body_for(event, who)
      parts = [who, group_name]
      parts << (event == 'created' ? date_time_label : date_label)
      parts.compact.reject(&:blank?).join(' · ')
    end

    def group_name
      @group_name ||= @schedule.group&.name.presence
    end

    def date_label
      @schedule.date_dimension&.date&.strftime('%d/%m')
    end

    def date_time_label
      d = date_label
      t = @schedule.scheduled_time.presence
      return d if t.nil?
      return "às #{t}" if d.nil?
      "#{d} às #{t}"
    end

    def session_url
      "/sessions/api-#{@schedule.id}"
    end

    # user_id => nome do 1º personagem dele nesta sessão.
    def character_names_by_user
      map = {}
      @schedule.characters.each { |c| map[c.user_id] ||= c.name if c.user_id.present? }
      map
    end

    def recipient_user_ids
      ids = @schedule.characters.map(&:user_id)
      ids << @schedule.group&.dm_user_id
      ids << @schedule.created_by_user_id
      ids = ids.compact.uniq
      dm_id = @schedule.group&.dm_user_id
      # Não notifica o autor da ação — salvo o Mestre, que recebe sempre.
      ids.delete(@actor_id) if @actor_id && @actor_id != dm_id
      ids
    end

    def recipients
      User.where(id: recipient_user_ids, notify_session_reminders: true)
          .where(id: PushSubscription.select(:user_id))
    end
  end
end
