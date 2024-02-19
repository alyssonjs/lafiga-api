class UsersController < ApplicationController
  before_action :authorize_request, except: :create
  before_action :find_user, except: %i[create index]

  def index
    @users = User.all
    render json: @users, status: :ok
  end

  def show
    render json: @user, status: :ok
  end

  def create
    @user = User.new(user_params)
    auth_token = JsonWebToken.encode(user_id: @user.id)
    if @user.save
      render json: { user: @user, message: Message.account_created, auth_token: auth_token }, status: :created
    else
      render json: { errors: @user.errors.full_messages },
              status: :unprocessable_entity
    end
  end

  def update
    unless @user.update(user_params)
      render json: { errors: @user.errors.full_messages },
              status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
  end

  private

  def find_user
    params[:_username]
    @user = User.find_by_username!(params[:_username])
    rescue ActiveRecord::RecordNotFound
      render json: { errors: 'User not found' }, status: :not_found
  end

  def user_params
    params.permit(
      :name, :username, :email, :password, :password_confirmation
    )
  end
end
