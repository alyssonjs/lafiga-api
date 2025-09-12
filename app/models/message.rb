class Message < ApplicationRecord
  enum kind: { user: 0, system: 1 }
  belongs_to :channel
  belongs_to :user
  validates :content, presence: true

  after_commit :broadcast_message, on: :create

  def author_name
    begin
      slug = channel.slug.to_s
      # Prefer character name contextual to group
      if slug =~ /^group-(\d+)$/
        gid = $1.to_i
        ch = Character.where(user_id: user_id, group_id: gid).first
        return ch.name if ch&.name.present?
      elsif slug =~ /^sheet-(\d+)$/
        sid = $1.to_i
        sh = Sheet.includes(:character).find_by(id: sid)
        if sh&.character && sh.character.user_id == user_id
          return sh.character.name if sh.character.name.present?
        end
      end
      # Fallbacks: user's name/username/email
      u = user
      return u.name if u.respond_to?(:name) && u.name.present?
      return u.username if u.respond_to?(:username) && u.username.present?
      return u.email if u.respond_to?(:email) && u.email.present?
    rescue => _e
      # ignore
    end
    "Usuário #{user_id}"
  end

  private
  def broadcast_message
    payload = {
      id: id,
      channel_id: channel_id,
      user_id: user_id,
      kind: kind,
      content: content,
      metadata: metadata,
      author_name: author_name,
      created_at: created_at.iso8601
    }
    ChatChannel.broadcast_to(channel, payload)
  rescue => e
    Rails.logger.warn("Chat broadcast failed: #{e.message}")
  end
end
