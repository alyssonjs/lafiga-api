# Be sure to restart your server when you modify this file.
#
# CORS for the SPA (front-lafiga). Origins differ per environment:
#   - development/test: localhost variants (Vite at :5173, legacy at :3000-3002)
#   - production: must come from FRONTEND_ORIGINS env (comma-separated full URLs)
#
# We send Authorization: Bearer <JWT> from the SPA, so credentials/expose are
# enabled. With credentials: true, "origins '*'" is forbidden by browsers, so
# we always pass concrete origins.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  if Rails.env.production?
    production_origins = ENV.fetch('FRONTEND_ORIGINS', '')
                            .split(',')
                            .map(&:strip)
                            .reject(&:empty?)

    if production_origins.any?
      allow do
        origins(*production_origins)

        resource '*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options, :head],
          credentials: true,
          expose: ['Authorization']
      end
    else
      Rails.logger.warn '[CORS] FRONTEND_ORIGINS is empty in production; SPA requests will be blocked.'
    end
  else
    allow do
      origins 'http://localhost:3000',
              'http://127.0.0.1:3000',
              'http://localhost:3001',
              'http://127.0.0.1:3001',
              'http://localhost:3002',
              'http://127.0.0.1:3002',
              # Vite dev server (front-lafiga)
              'http://localhost:5173',
              'http://127.0.0.1:5173'

      resource '*',
        headers: :any,
        methods: [:get, :post, :put, :patch, :delete, :options, :head],
        credentials: true,
        expose: ['Authorization']
    end
  end
end
