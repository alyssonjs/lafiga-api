# frozen_string_literal: true

module Push
  # Envia UMA notificação Web Push para TODAS as assinaturas de um usuário.
  # Limpa endpoints mortos (404/410/expirado). Config VAPID vem do ENV; no-op se
  # não configurado. Síncrono de propósito — o chamador (rake via cron) é um
  # processo curto, então não usamos ActiveJob :async (as threads morreriam ao sair).
  class Sender
    DEAD_CODES = [404, 410].freeze
    DEFAULT_TTL = 24 * 60 * 60 # segundos

    def self.call(user:, title:, body:, url: '/', tag: nil)
      new(user: user, title: title, body: body, url: url, tag: tag).call
    end

    def initialize(user:, title:, body:, url:, tag:)
      @user = user
      @payload = { title: title, body: body, url: url, tag: tag }.compact.to_json
    end

    # Retorna quantas assinaturas receberam com sucesso.
    def call
      return 0 unless self.class.vapid_configured?

      sent = 0
      @user.push_subscriptions.find_each { |sub| sent += 1 if deliver(sub) }
      sent
    end

    def self.vapid_configured?
      ENV['VAPID_PUBLIC_KEY'].present? && ENV['VAPID_PRIVATE_KEY'].present?
    end

    def self.vapid_public_key
      ENV['VAPID_PUBLIC_KEY']
    end

    private

    def deliver(sub)
      WebPush.payload_send(
        message: @payload,
        endpoint: sub.endpoint,
        p256dh: sub.p256dh_key,
        auth: sub.auth_key,
        vapid: vapid_options,
        ttl: DEFAULT_TTL,
      )
      sub.update_column(:last_seen_at, Time.current)
      true
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      sub.destroy
      false
    rescue WebPush::ResponseError => e
      code = e.response&.code.to_i
      sub.destroy if DEAD_CODES.include?(code)
      Rails.logger.warn("[Push::Sender] ResponseError code=#{code} sub=#{sub.id}")
      false
    rescue StandardError => e
      Rails.logger.warn("[Push::Sender] #{e.class}: #{e.message} sub=#{sub.id}")
      false
    end

    def vapid_options
      {
        subject: ENV.fetch('VAPID_SUBJECT', 'mailto:contato@lafiga.com.br'),
        public_key: ENV['VAPID_PUBLIC_KEY'],
        private_key: ENV['VAPID_PRIVATE_KEY'],
      }
    end
  end
end
