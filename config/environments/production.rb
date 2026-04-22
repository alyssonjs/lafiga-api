Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in either ENV["RAILS_MASTER_KEY"]
  # or in config/master.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = 'http://assets.example.com'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = 'X-Sendfile' # for Apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options)
  config.active_storage.service = :local

  # ActionCable origins must match the SPA host(s) that connect over WebSocket.
  # Set ACTION_CABLE_ALLOWED_ORIGINS as a comma-separated list of fully-qualified
  # origins (e.g. "https://app.lafiga.app,https://staging.lafiga.app"). The
  # browser blocks WSS unless the SPA is also on HTTPS; keep wss:// + https://
  # in production.
  cable_origins = ENV.fetch('ACTION_CABLE_ALLOWED_ORIGINS', '').split(',').map(&:strip).reject(&:empty?)
  config.action_cable.allowed_request_origins = cable_origins if cable_origins.any?
  # If you serve the cable from a different host than the API:
  # config.action_cable.url = ENV['ACTION_CABLE_URL'] # e.g. 'wss://api.lafiga.app/cable'

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # Disable when behind a TLS-terminating proxy that injects X-Forwarded-Proto correctly,
  # or when running on platforms that don't support force_ssl headers (e.g. local Docker).
  config.force_ssl = ENV.fetch('FORCE_SSL', 'true') == 'true'

  # Default to :info in production. Set RAILS_LOG_LEVEL=debug for incident triage.
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info').to_sym

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # Use Redis as the cache store when REDIS_URL is set (Rails caches, fragment caches).
  # We use a separate logical DB (default /2) to avoid colliding with Action Cable (/1).
  if ENV['REDIS_URL'].present?
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch('CACHE_REDIS_URL') { ENV['REDIS_URL'] },
      namespace: 'lafiga-cache',
      expires_in: 1.day,
      reconnect_attempts: 1,
      error_handler: ->(method:, returning:, exception:) {
        Rails.logger.error("[redis_cache_store] #{method} failed: #{exception.class} #{exception.message}")
      }
    }
  end

  # Use a real queuing backend for Active Job (and separate queues per environment)
  # config.active_job.queue_adapter     = :resque
  # config.active_job.queue_name_prefix = "lafiga-api_#{Rails.env}"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Use a different logger for distributed setups.
  # require 'syslog/logger'
  # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new 'app-name')

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger           = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false
end
