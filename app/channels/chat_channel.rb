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

  # Authenticates the JWT passed via `params[:token]` (subscribe payload).
  # Uses the same JsonWebToken helper + blacklist as the HTTP layer
  # (ApiRequestAuth) so that revoking a token via ValidateJwtToken also
  # cuts off the WebSocket subscription.
  def authenticate_token(token)
    return nil if token.blank?
    return nil if ValidateJwtToken.where(token: token).exists?

    payload = JsonWebToken.decode(token)
    uid = payload[:user_id] || payload[:id]
    User.find_by(id: uid)
  rescue ExceptionHandler::InvalidToken, JWT::DecodeError, StandardError
    nil
  end
end

