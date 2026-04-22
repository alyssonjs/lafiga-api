# frozen_string_literal: true

# Site-wide DM grants "you may level up" for a character (milestone). One row per character.
class CharacterDmLevelUnlock < ApplicationRecord
  belongs_to :character
  belongs_to :unlocked_by_user, class_name: 'User'

  validates :character_id, uniqueness: true
  validate :unlocked_by_must_be_site_dm

  private

  def unlocked_by_must_be_site_dm
    return if unlocked_by_user.blank?

    return if Group.user_is_dm?(unlocked_by_user)

    errors.add(:unlocked_by_user, 'must be a site-wide DM or Admin')
  end
end
