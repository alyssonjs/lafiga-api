require 'rails_helper'

RSpec.describe Group, type: :model do
  describe '#member?' do
    let(:group) { create(:group) }
    let(:user)  { create(:user) }

    it 'returns true when the user owns at least one character in the group' do
      create(:character, user: user, group: group)
      expect(group.member?(user)).to be true
    end

    it 'returns false when the user has no character in the group' do
      other_group = create(:group)
      create(:character, user: user, group: other_group)
      expect(group.member?(user)).to be false
    end

    it 'returns false for nil user' do
      expect(group.member?(nil)).to be false
    end

    it 'returns false for an unsaved group' do
      unsaved = build(:group)
      expect(unsaved.member?(user)).to be false
    end

    it 'returns true when the user is the dm_user_id (owner) even without a character' do
      owner = create(:user)
      owned = create(:group, dm_user_id: owner.id)
      expect(owned.member?(owner)).to be true
    end

    it 'returns false when dm_user_id matches a different user' do
      owner = create(:user)
      stranger = create(:user)
      owned = create(:group, dm_user_id: owner.id)
      expect(owned.member?(stranger)).to be false
    end
  end

  describe '#owned_by?' do
    it 'returns true only for the user matching dm_user_id' do
      owner = create(:user)
      stranger = create(:user)
      group = create(:group, dm_user_id: owner.id)

      expect(group.owned_by?(owner)).to be true
      expect(group.owned_by?(stranger)).to be false
      expect(group.owned_by?(nil)).to be false
    end

    it 'returns false when dm_user_id is nil (legacy seed)' do
      group = create(:group, dm_user_id: nil)
      user  = create(:user)
      expect(group.owned_by?(user)).to be false
    end
  end

  describe '.user_is_dm? / #dm?' do
    let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
    let(:admin_role)  { Role.find_or_create_by!(name: 'Admin') }
    let(:player_role) { Role.find_or_create_by!(name: 'Player') }

    let(:group)  { create(:group) }
    let(:dm)     { create(:user, role: dm_role) }
    let(:admin)  { create(:user, role: admin_role) }
    let(:player) { create(:user, role: player_role) }

    it 'returns true for users with the DM role (canonical)' do
      expect(Group.user_is_dm?(dm)).to be true
      expect(group.dm?(dm)).to be true
    end

    it 'returns true for users with the legacy Admin role (alias)' do
      expect(group.dm?(admin)).to be true
    end

    it 'returns false for Player users even when they have a character in the group' do
      create(:character, user: player, group: group)
      expect(group.dm?(player)).to be false
    end

    it 'returns false for nil user' do
      expect(group.dm?(nil)).to be false
    end

    it 'is site-wide: a DM is DM of any group, not just where they have characters' do
      other_group = create(:group)
      expect(other_group.dm?(dm)).to be true
    end
  end

  describe '#can_master?' do
    let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
    let(:player_role) { Role.find_or_create_by!(name: 'Player') }

    it 'returns true for any DM' do
      dm = create(:user, role: dm_role)
      group = create(:group)
      expect(group.can_master?(dm)).to be true
    end

    it 'returns false for Player users (even members of the group)' do
      player = create(:user, role: player_role)
      group = create(:group)
      create(:character, user: player, group: group)
      expect(group.can_master?(player)).to be false
    end

    it 'returns false for nil user' do
      expect(create(:group).can_master?(nil)).to be false
    end
  end

  describe '#member_user_ids' do
    let(:group) { create(:group) }

    it 'returns distinct user ids of all members' do
      u1 = create(:user)
      u2 = create(:user)
      create(:character, user: u1, group: group)
      create(:character, user: u1, group: group) # duplicate
      create(:character, user: u2, group: group)

      expect(group.member_user_ids).to contain_exactly(u1.id, u2.id)
    end

    it 'returns an empty array when the group has no characters' do
      expect(group.member_user_ids).to eq([])
    end
  end
end
