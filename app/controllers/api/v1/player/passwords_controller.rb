# frozen_string_literal: true

module Api
  module V1
    module Player
      # Troca de senha do proprio utilizador (requer senha actual). 422 para
      # credencial errada ou validacao — nunca 401, para o cliente nao limpar a sessao.
      class PasswordsController < ApplicationController
        before_action :authorize_request

        def update
          p = password_params
          if p[:current_password].blank? || p[:password].blank? || p[:password_confirmation].blank?
            return render json: { errors: ['current_password, password e password_confirmation sao obrigatorios.'] },
                          status: :unprocessable_entity
          end

          unless @current_user.authenticate(p[:current_password])
            return render json: { errors: ['Senha actual incorrecta.'] }, status: :unprocessable_entity
          end

          @current_user.password = p[:password]
          @current_user.password_confirmation = p[:password_confirmation]

          if @current_user.save
            render json: {
              message: 'Senha actualizada com sucesso.',
              password_changed_at: @current_user.password_changed_at&.iso8601(3)
            }, status: :ok
          else
            render json: { errors: @current_user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def password_params
          params.permit(:current_password, :password, :password_confirmation)
        end
      end
    end
  end
end
