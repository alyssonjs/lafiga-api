class Channel < ApplicationRecord
  enum kind: { public_channel: 0, private_channel: 1, direct: 2 }

  has_many :channel_memberships, dependent: :destroy
  has_many :users, through: :channel_memberships
  has_many :messages, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  def visible_to?(user)
    return true if public_channel?
    return true if user.respond_to?(:role) && user.role && user.role.name == 'Admin'
    return users.exists?(user.id) if private_channel? || direct?
    false
  end

  def self.direct_between(a_id, b_id)
    ids = [a_id, b_id].map(&:to_i).sort
    slug = "dm-#{ids[0]}-#{ids[1]}"
    name = "DM #{ids[0]}-#{ids[1]}"
    ch = Channel.find_or_create_by!(slug: slug) { |c| c.name = name; c.kind = :direct }
    ids.each { |uid| ch.channel_memberships.find_or_create_by!(user_id: uid) }
    ch
  end
end
