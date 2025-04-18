class Api::V1::Admin::UsersController < ApplicationController
    before_action :authorize_admin_request
    before_action :get_user, only: [:show, :update, :destroy]
  
    def index
      #TODO  change all to pagination
      users = User.all
      render json: {users: users}, include: [:role, :characters], status: 200 
    end
  
    def show
      render json: {user: @user}, status: 200
    end
  
    def update
      if @user.update(user_params)
        render json: {user: @user}, status: 200
      else
        render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
      end
    rescue StandardError => e
      render json: {errors: e.message}
    end

    private

    def user_params
      params.require(:user).permit(
        :name, :username, :phone, :email, :role_id
      )
    end
  
    def get_user
      @user = User.find(params[:id])
    rescue StandardError => e 
      render json: { errors: e.message }, status: :not_found
    end
end
