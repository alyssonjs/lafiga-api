class ApplicationController < ActionController::API
    require 'open-uri'

    include ExceptionHandler

    # ZC3 do segundo audit: a versao antiga renderizava 200 OK com `{ error: 'not_found' }`,
    # quebrando contrato HTTP. Clientes que tratam erro pelo status passavam por essa
    # resposta como sucesso. O catch-all `/*a` em routes.rb caia aqui — qualquer URL
    # invalida virava "200 sem dado". Agora respondemos 404 explicito.
    def not_found
        render json: { error: 'not_found' }, status: :not_found
    end

    # Padroniza respostas JSON; usado pelos handlers do ExceptionHandler.
    def json_response(payload, status = :ok)
        render json: payload, status: status
    end

    def authorize_request
        @current_user = ApiRequestAuth.call(request.headers).result

        render json: { error: 'Access deneid! Please, sign in to update your credentials.' }, status: 401 unless @current_user
    end

    def authorize_admin_request
        @current_user = ApiRequestAuth.call(request.headers).result
        
        unless @current_user
            render json: { error: 'Access deneid! Please, sign in to update your credentials.' }, status: 401
            return
        end

        render json: { error: 'Access deneid! You must be an administator.' }, status: 401 if @current_user.role.name != "Admin"
    end

    # Mestre (DM) ou Admin do site — mesmo criterio de Group.user_is_dm?.
    # Usado em endpoints onde o jogador comum nao pode criar recurso (ex.: nova algibeira).
    def authorize_site_wide_dm
      @current_user = ApiRequestAuth.call(request.headers).result
      unless @current_user
        render json: { error: 'Access deneid! Please, sign in to update your credentials.' }, status: 401
        return
      end

      return if Group.user_is_dm?(@current_user)

      render json: { error: 'Access denied. DM or Admin only.' }, status: 403
    end

    # Dono do personagem da ficha ou Mestre (DM/Admin do site) — mesmo critério de
    # SheetsController#sheets_scope_for_current_user e GET/PATCH em sheets alheias.
    def current_user_may_access_sheet?(sheet)
      return false if sheet.nil? || @current_user.nil?

      sheet.character.user_id == @current_user.id || Group.user_is_dm?(@current_user)
    end
end
