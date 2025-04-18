class Api::V1::Admin::RolesController < ApplicationController
    before_action :authorize_admin_request
  
    def index
      #TODO  change all to pagination
      roles = Role.all
      render json: {roles: roles}, status: 200 
    end
end
