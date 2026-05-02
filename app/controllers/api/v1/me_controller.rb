# frozen_string_literal: true

module Api
  module V1
    # Single-source-of-truth do estado de autenticação a partir do servidor.
    #
    # O front guardava `role`/`permissions` em localStorage e gateava UI por isso —
    # qualquer adulteração local (`localStorage.setItem('role', 'admin')`) fazia
    # a UI mostrar painel de DM (mutations continuavam sendo bloqueadas pelo
    # backend, mas era confuso e dava falsa sensação de privilégio).
    #
    # Com este endpoint o front passa a derivar `role`/`permissions` direto da
    # resposta autoritativa do servidor — não confia mais em localStorage para
    # gates de UI. Veja `front-lafiga/src/app/context/UserContext.tsx`.
    #
    # `authorize_request` já recarrega `User` + `role` do DB a cada request,
    # então não há cache nem possibilidade de claim adulterado: o JWT só
    # carrega `user_id`.
    class MeController < ApplicationController
      include RoleSerializer

      before_action :authorize_request

      # GET /api/v1/me
      # Retorna o mesmo schema do payload de login para o front reusar
      # `mapUserInfosToAuthUser` sem ramificações. Diferença intencional vs.
      # `AuthenticationController#login`: filtra `password_digest` da
      # serialização. O login antigo vaza esse campo (bug pré-existente
      # rastreado em follow-up); aqui não introduzimos a regressão.
      def show
        render json: {
          user_infos: @current_user.as_json(except: SENSITIVE_USER_FIELDS),
          role: serialize_role(@current_user.role.name),
          permissions: @current_user.role.permissions
        }, status: :ok
      end

      private

      SENSITIVE_USER_FIELDS = %i[password_digest password_changed_at].freeze
      private_constant :SENSITIVE_USER_FIELDS
    end
  end
end
