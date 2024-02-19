class AuthenticationController < ApplicationController
  before_action :authorize_request, except: [:login, :logout]

  def login
    @user = User.find_by_email(params[:email])
    if @user&.authenticate(params[:password])

      token = JsonWebToken.encode(user_id: @user.id)
      time = Time.now + 24.hours.to_i
      render json: { token: token, message: 'Login success!',
                      exp: time.strftime("%m-%d-%Y %H:%M"),
                      user_infos: @user }, 
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

  private
  
  attr_accessor :email, :password

  def login_params
    params.permit(:email, :password)
  end
end
