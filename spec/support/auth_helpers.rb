# frozen_string_literal: true

module AuthHelpers
  # ApiRequestAuth espera header "Authorization: Bearer <jwt>"; tokens na blacklist (ValidateJwtToken) falham.
  def bearer_headers_for(user)
    token = JsonWebToken.encode({ user_id: user.id })
    { 'Authorization' => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
