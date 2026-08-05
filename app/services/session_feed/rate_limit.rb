# frozen_string_literal: true

module SessionFeed
  # Throttle feed_item performs per user + schedule.
  # Prefer Redis when REDIS_URL is set (Docker dev / production) so limits work
  # even with development's default cache_store :null_store. Otherwise Rails.cache.
  class RateLimit
    LIMIT = 60
    WINDOW_SECONDS = 60
    # Bucket próprio p/ o stream de preview de área (mouse-move): alta frequência,
    # efêmero, NÃO pode consumir o bucket compartilhado do chat/rolls. ~20/s.
    AOE_PREVIEW_LIMIT = 1_200

    class << self
      # `bucket` isola contadores por classe de tráfego (default = chat/rolls);
      # `limit` permite um teto próprio (ex.: preview de área). Retrocompatível.
      def allow?(user_id, schedule_id, bucket: 'default', limit: LIMIT)
        return true if user_id.blank? || schedule_id.blank?

        window = Time.current.to_i / WINDOW_SECONDS
        key = "session_feed/v1/#{bucket}/#{user_id}/#{schedule_id}/#{window}"

        if use_redis?
          allow_via_redis!(key, limit)
        else
          allow_via_cache!(key, limit)
        end
      end

      private

      def use_redis?
        ENV['REDIS_URL'].to_s.present? && !Rails.env.test?
      end

      def allow_via_redis!(key, limit)
        r = redis_client
        n = r.incr(key)
        r.expire(key, WINDOW_SECONDS * 2) if n == 1
        n <= limit
      rescue Redis::BaseError => e
        Rails.logger.warn({ event: 'session_feed.rate_limit_redis_error', error: e.class.name, message: e.message }.to_json)
        true
      end

      def allow_via_cache!(key, limit)
        count = Rails.cache.read(key).to_i
        return false if count >= limit

        Rails.cache.write(key, count + 1, expires_in: (WINDOW_SECONDS * 2).seconds)
        true
      end

      def redis_client
        @redis_client ||= Redis.new(url: ENV.fetch('REDIS_URL'))
      end
    end
  end
end
