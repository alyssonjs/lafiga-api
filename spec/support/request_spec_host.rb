# frozen_string_literal: true

# Evita Rack::HostAuthorization / ActionDispatch bloqueando o host padrão do Rack::Test.
RSpec.configure do |config|
  config.before(:each, type: :request) do
    host! 'localhost'
  end
end
