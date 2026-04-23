# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionFeed::RateLimit do
  around do |example|
    old_cache = Rails.cache
    old_redis_url = ENV.fetch('REDIS_URL', nil)
    ENV.delete('REDIS_URL')
    clear_session_feed_redis_client
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = old_cache
    if old_redis_url
      ENV['REDIS_URL'] = old_redis_url
    else
      ENV.delete('REDIS_URL')
    end
    clear_session_feed_redis_client
  end

  def clear_session_feed_redis_client
    sc = SessionFeed::RateLimit.singleton_class
    sc.send(:remove_instance_variable, :@redis_client) if sc.instance_variable_defined?(:@redis_client)
  end

  it 'allows up to LIMIT messages per window' do
    uid = 42
    sid = 7
    described_class::LIMIT.times do
      expect(described_class.allow?(uid, sid)).to be true
    end
    expect(described_class.allow?(uid, sid)).to be false
  end
end
