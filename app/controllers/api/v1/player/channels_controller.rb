class Api::V1::Player::ChannelsController < ApplicationController
  before_action :authorize_request

  def index
    if @current_user.role&.name == 'Admin'
      visible = Channel.all
    else
      visible = Channel.left_joins(:channel_memberships)
        .where("channels.kind = ? OR channel_memberships.user_id = ?", Channel.kinds[:public_channel], @current_user.id)
        .distinct
    end
    render json: { channels: visible.as_json(only: [:id, :name, :slug, :kind]) }, status: :ok
  end

  def create
    ch = Channel.find_or_initialize_by(slug: permitted[:slug])
    if ch.name.blank?
      # Default friendly names by slug pattern
      slug = permitted[:slug].to_s
      if slug == 'general'
        ch.name = 'General'
      elsif slug =~ /^group-(\d+)$/
        gid = $1.to_i
        g = Group.find_by(id: gid)
        ch.name = g ? "Grupo: #{g.name}" : slug
      elsif slug =~ /^sheet-(\d+)$/
        sid = $1.to_i
        sh = Sheet.includes(:character).find_by(id: sid)
        ch.name = sh&.character&.name.presence || "Sheet ##{sid}"
      else
        ch.name = permitted[:name].presence || slug
      end
    end
    ch.kind = permitted[:kind] if permitted[:kind]
    ch.kind ||= :public_channel
    ch.save!
    # Ensure membership for creator in private/direct
    if ch.private_channel? || ch.direct?
      ch.channel_memberships.find_or_create_by!(user_id: @current_user.id)
    end
    render json: { channel: ch.as_json(only: [:id, :name, :slug, :kind]) }, status: :created
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def direct
    other_id = params[:user_id].to_i
    if other_id <= 0
      return render json: { error: 'user_id inválido' }, status: :unprocessable_entity
    end
    ch = Channel.direct_between(@current_user.id, other_id)
    render json: { channel: ch.as_json(only: [:id, :name, :slug, :kind]) }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private
  def permitted
    params.require(:channel).permit(:name, :slug, :kind)
  end
end
