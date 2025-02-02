class ApplicationController < ActionController::API
    require 'open-uri'

    def not_found
        render json: { error: 'not_found' }
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
end
  