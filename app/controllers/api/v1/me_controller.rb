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

      # PATCH /api/v1/me/ui_preferences
      # Grava preferências de UI da própria conta. Os atalhos de fichas são uma
      # ferramenta exclusiva do mestre e ficam isolados por sessão.
      def update_ui_preferences
        if params.key?(:floating_sheet_pins) && !Group.user_is_dm?(@current_user)
          return render json: { error: 'Acesso restrito ao Mestre.' }, status: :forbidden
        end

        @current_user.set_combat_hotbar_pref!(params[:combat_hotbar]) if params.key?(:combat_hotbar)

        if params.key?(:floating_sheet_pins)
          pins = params.require(:floating_sheet_pins).permit(:session_id, character_ids: [])
          @current_user.set_floating_sheet_pins_pref!(pins[:session_id], pins[:character_ids])
        end

        render json: me_payload, status: :ok
      rescue ActionController::ParameterMissing, ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity
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
