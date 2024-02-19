class ValidateJwtToken < ApplicationRecord
    after_commit :clear_tokens

    def clear_tokens
        time = Time.now - 1.day
        ValidateJwtToken.where("created_at <= '#{time}'").destroy_all
    end
end
