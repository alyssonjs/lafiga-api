# frozen_string_literal: true

module SessionFeed
  # Throttle feed_item performs per user + schedule.
  # Prefer Redis when REDIS_URL is set (Docker dev / production) so limits work
  # even with development's default cache_store :null_store. Otherwise Rails.cache.
  class RateLimit
    LIMIT = 60
    WINDOW_SECONDS = 60

    class << self
      def allow?(user_id, schedule_id)
        return true if user_id.blank? || schedule_id.blank?

        window = Time.current.to_i / WINDOW_SECONDS
        key = "session_feed/v1/#{user_id}/#{schedule_id}/#{window}"

        if use_redis?
          allow_via_redis!(key)
        else
          allow_via_cache!(key)
        end
      end

      private

      def use_redis?
        ENV['REDIS_URL'].to_s.present? && !Rails.env.test?
      end

      def allow_via_redis!(key)
        r = redis_client
        n = r.incr(key)
        r.expire(key, WINDOW_SECONDS * 2) if n == 1
        n <= LIMIT
      rescue Redis::BaseError => e
        Rails.logger.warn({ event: 'session_feed.rate_limit_redis_error', error: e.class.name, message: e.message }.to_json)
        true
      end

      def allow_via_cache!(key)
        count = Rails.cache.read(key).to_i
        return false if count >= LIMIT

        Rails.cache.write(key, count + 1, expires_in: (WINDOW_SECONDS * 2).seconds)
        true
      end

      def redis_client
        @redis_client ||= Redis.new(url: ENV.fetch('REDIS_URL'))
      end
    end
  end
end
