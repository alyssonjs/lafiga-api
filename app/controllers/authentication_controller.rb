class AuthenticationController < ApplicationController
  before_action :authorize_request, except: [:login, :logout, :signup]

  def login
    @user = User.find_by_email(params[:email])
    if @user&.authenticate(params[:password])

      token = JsonWebToken.encode(user_id: @user.id)
      time = Time.now + 24.hours.to_i
      render json: { token: token, message: 'Login success!',
                      exp: time.strftime("%m-%d-%Y %H:%M"),
                      user_infos: @user,
                      role: @user.role.name,
                      permissions: @user.role.permissions
                    },
                      status: :ok
    else
      render json: { error: 'unauthorized' }, status: :unauthorized
    end
  end

  def logout
    revoke = ValidateJwtToken.find_by(token: request.headers['Authorization'])
    if revoke
      render json: { message: 'Logout sucessfull!' }, status: :ok
    else
      render json: { error: 'Invalid credentials!' }, status: :unauthorized
    end
  end

  def signup
    @user = User.new(signup_params)
    if @user.save

      token = JsonWebToken.encode(user_id: @user.id)
      exp   = 24.hours.from_now.strftime("%m-%d-%Y %H:%M")

      render json: {
        token:        token,
        message:      'Signup realizado com sucesso!',
        exp:          exp,
        user_infos:   @user,
        role:         @user.role.name,
        permissions:  @user.role.permissions
      }, status: :created
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
  
  attr_accessor :email, :password

  def login_params
    params.permit(:email, :password)
  end

  def signup_params
    params.permit(:name, :username, :email, :password, :password_confirmation, :role_id)
  end
end
