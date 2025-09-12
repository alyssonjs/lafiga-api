class Group < ApplicationRecord
  enum season: { verao: 0, inverno: 1, primavera: 2, outono: 3 }

  validates :name, presence: true
  validates :day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }

  has_one :schedule
  has_many :characters

  after_commit :ensure_chat_channel!, on: :create
  after_commit :sync_channel_memberships!, on: :create

  # Returns the slug for this group's channel
  def chat_slug
    "group-#{id}"
  end

  # Finds or creates the private channel for this group
  def ensure_chat_channel!
    return if id.nil?
    ch = Channel.find_or_initialize_by(slug: chat_slug)
    ch.name = name.present? ? "Grupo: #{name}" : chat_slug if ch.name.blank?
    ch.kind = :private_channel
    ch.save!
    ch
  end

  # Ensures all users who have characters in this group are members of the channel
  def sync_channel_memberships!
    ch = ensure_chat_channel!
    user_ids = characters.includes(:user).map(&:user_id).uniq
    user_ids.each do |uid|
      ch.channel_memberships.find_or_create_by!(user_id: uid)
    end
  end
end
