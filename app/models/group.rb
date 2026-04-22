class Group < ApplicationRecord
  enum season: { verao: 0, inverno: 1, primavera: 2, outono: 3 }

  validates :name, presence: true
  validates :day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 120 }

  has_many :schedules, dependent: :nullify
  has_many :characters
  has_many :campaign_notes, dependent: :destroy
  has_many :battle_maps, dependent: :nullify

  # Capa da campanha (Fase 4c). `cover_image_url` continua existindo para o
  # legado/seed e como fallback para URLs externas (Imgur/Unsplash) — o
  # serializer escolhe `cover_image.url > cover_image_url` em ordem.
  # `service_url(expires_in: nil)` evitaria expiry, mas como usamos disco
  # local em dev/prod, o url helper devolve `/rails/active_storage/blobs/...`
  # que não tem expiração de fato.
  has_one_attached :cover_image

  # Criador/dono do grupo. Setado em Api::V1::Player::GroupsController#create.
  # `optional: true` para preservar grupos legados (seed antigo) que ainda não
  # têm dm_user_id populado. Player que criou o grupo enxerga ele em /index e
  # passa por #set_group mesmo sem ter Character vinculado ainda.
  belongs_to :dm_user, class_name: 'User', optional: true

  after_commit :ensure_chat_channel!, on: :create
  after_commit :sync_channel_memberships!, on: :create

  # Membership = the user owns at least one Character in this group.
  # This is the canonical authorization check for read-only group-scoped
  # resources (chat channel, realtime session channels, campaign notes, etc.).
  #
  # Returns false for nil users so callers can chain safely:
  #   schedule.group&.member?(current_user)
  def member?(user)
    return false if user.nil? || id.nil?
    return true if dm_user_id.present? && dm_user_id == user.id
    characters.exists?(user_id: user.id)
  end

  # `true` se o usuário é o criador/owner deste grupo (DM da campanha).
  # Distinto de `dm?` (papel global do site). Usado no controller para
  # autorizar leitura/escrita de grupos sem Character vinculado.
  def owned_by?(user)
    return false if user.nil? || dm_user_id.nil?
    dm_user_id == user.id
  end

  # DM is a SITE-WIDE role (not per-group). The DM is the admin of the entire
  # platform — they can master any group/session. Players see their own
  # campaigns; the DM sees all of them.
  #
  # Identification is via `User.role.name`:
  #   - "DM"    => canonical (added in seeds.rb)
  #   - "Admin" => legacy alias kept for backwards compat with existing seeds
  #
  # Use this on write endpoints of combat/session resources where only the DM
  # may mutate state.
  def self.user_is_dm?(user)
    return false if user.nil?
    return false unless user.respond_to?(:role) && user.role
    %w[DM Admin].include?(user.role.name)
  end

  # Instance shortcut. Note: ignores `self` — DM authority is global.
  # Kept as instance method for ergonomic call sites: `group.dm?(current_user)`.
  def dm?(user)
    self.class.user_is_dm?(user)
  end

  # Read+Write authorization: DM has it everywhere, plus the user must be a
  # member of THIS group (so a DM with multiple groups doesn't accidentally
  # operate on someone else's session — DM is site-wide but actions still
  # require being in the right room).
  def can_master?(user)
    return false if user.nil?
    self.class.user_is_dm?(user)
  end

  # Distinct user IDs of members. Useful when broadcasting/syncing memberships.
  def member_user_ids
    characters.distinct.pluck(:user_id).compact
  end

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
