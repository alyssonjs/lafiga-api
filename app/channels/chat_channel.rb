class ChatChannel < ApplicationCable::Channel
  def subscribed
    token = params[:token].to_s
    @current_user = authenticate_token(token)
    reject unless @current_user

    channel = find_channel
    reject unless channel && channel.visible_to?(@current_user)

    stream_for channel
  end

  private
  def find_channel
    if params[:channel_id].present?
      Channel.find_by(id: params[:channel_id])
    elsif params[:channel_slug].present?
      Channel.find_by(slug: params[:channel_slug])
    end
  end

  def authenticate_token(token)
    return nil if token.blank?
    secret = ENV['JWT_SECRET'] || Rails.application.secret_key_base
    begin
      decoded = JWT.decode(token, secret, true, { algorithm: 'HS256' })
      payload = decoded[0] || {}
      uid = payload['user_id'] || payload['id']
      User.find_by(id: uid)
    rescue => _e
      nil
    end
  end
end

