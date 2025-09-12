class Api::V1::Player::ChannelMessagesController < ApplicationController
  before_action :authorize_request
  before_action :set_channel

  def index
    unless @channel.visible_to?(@current_user)
      return render json: { error: 'Forbidden' }, status: :forbidden
    end
    scope = @channel.messages.includes(:user).order(:created_at)
    scope = scope.where('id > ?', params[:after_id]) if params[:after_id].present?
    render json: { messages: scope.map { |m| serialize(m) } }, status: :ok
  end

  def create
    unless @channel.visible_to?(@current_user)
      return render json: { error: 'Forbidden' }, status: :forbidden
    end
    msg = @channel.messages.create!(user: @current_user, content: permitted[:content])
    process_commands(msg)
    render json: { message: serialize(msg) }, status: :created
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private
  def set_channel
    @channel = Channel.find(params[:channel_id])
  end

  def permitted
    params.require(:message).permit(:content)
  end

  def serialize(m)
    { id: m.id,
      user_id: m.user_id,
      channel_id: m.channel_id,
      content: m.content,
      kind: m.kind,
      metadata: m.metadata,
      author_name: (m.respond_to?(:author_name) ? m.author_name : nil),
      created_at: m.created_at }
  end

  def process_commands(msg)
    if msg.content.to_s.strip.start_with?('!')
      res = Chat::CommandProcessor.call(msg.content.to_s.strip)
      if res
        msg.channel.messages.create!(user: msg.user, kind: :system, content: res[:text], metadata: res)
      end
    end
  rescue => e
    Rails.logger.warn("Command processing failed: #{e.message}")
  end
end
