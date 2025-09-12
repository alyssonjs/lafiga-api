class Character < ApplicationRecord

  validates :name,:background, presence: true
  
  belongs_to :user
  belongs_to :group, optional: true
  
  has_one :sheet
  has_one :schedule_character

  after_save :sync_group_channel_membership, if: :saved_change_to_group_id?

  private
  def sync_group_channel_membership
    old_id, new_id = saved_change_to_group_id
    # Remove from old group's channel
    if old_id.present?
      if (old_group = Group.find_by(id: old_id))
        if (ch = Channel.find_by(slug: old_group.chat_slug))
          ChannelMembership.where(user_id: user_id, channel_id: ch.id).delete_all
        end
      end
    end
    # Add to new group's channel
    if new_id.present?
      if (new_group = Group.find_by(id: new_id))
        ch = new_group.ensure_chat_channel!
        ch.channel_memberships.find_or_create_by!(user_id: user_id)
      end
    end
  end
end
