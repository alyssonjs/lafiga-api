# frozen_string_literal: true

module Api
  module V1
    module Player
      # Actualiza nome e email do utilizador autenticado (sem passar :username no URL).
      class ProfilesController < ApplicationController
        before_action :authorize_request

        def update
          unless @current_user.update(profile_params)
            return render json: { errors: @current_user.errors.full_messages },
                          status: :unprocessable_entity
          end

          render json: {
            name: @current_user.name,
            email: @current_user.email,
            username: @current_user.username
          }, status: :ok
        end

        private

        def profile_params
          params.permit(:name, :email)
        end
      end
    end
  end
end
