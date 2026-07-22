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
      # `mapUserInfosToAuthUser` sem ramificações. Filtragem de campos
      # sensíveis (bcrypt hash) via `User::SENSITIVE_API_FIELDS` —
      # mesma constante usada em `AuthenticationController#login`/`#signup`
      # depois do PR C.
      def show
        render json: me_payload, status: :ok
      end

      # PATCH /api/v1/me/ui_preferences  { combat_hotbar: true|false }
      # Grava preferências de UI da própria conta. `combat_hotbar` ativa o novo
      # hotbar de combate; é inócua para não-DM (o front nunca renderiza o hotbar
      # sem `role === 'dm'`), então qualquer usuário autenticado pode gravá-la.
      def update_ui_preferences
        @current_user.set_combat_hotbar_pref!(params[:combat_hotbar]) if params.key?(:combat_hotbar)
        render json: me_payload, status: :ok
      end

      private

      def me_payload
        {
          user_infos: @current_user.as_json(except: User::SENSITIVE_API_FIELDS),
          role: serialize_role(@current_user.role.name),
          permissions: @current_user.role.permissions
        }
      end
    end
  end
end
