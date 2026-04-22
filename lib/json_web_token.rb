class JsonWebToken
  SECRET_KEY = Rails.application.secrets.secret_key_base.to_s

  # Override with ENV['JWT_EXPIRATION_DAYS'] (integer days, default 30).
  def self.default_expiration
    ENV.fetch('JWT_EXPIRATION_DAYS', '30').to_i.clamp(1, 365).days.from_now
  end

  def self.encode(payload, exp = nil)
    exp ||= default_expiration
    payload[:exp] = exp.to_i
    JWT.encode(payload, SECRET_KEY)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY)[0]
    HashWithIndifferentAccess.new decoded
    
  rescue JWT::DecodeError => e

    raise ExceptionHandler::InvalidToken, e.message
  end
end
