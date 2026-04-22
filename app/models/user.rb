class User < ApplicationRecord
    has_secure_password

    validates :email, presence: true, uniqueness: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :username, presence: true, uniqueness: true
    validates :role_id, presence: true

    has_many :characters
    has_many :groups, through: :characters
    # Grupos onde este usuário é o DM (criador/dono). Distinto de `:groups`,
    # que são grupos onde o usuário tem characters. O criador entra aqui quando
    # um mestre (papel site-wide DM/Admin) cria o grupo via API, mesmo sem
    # personagem vinculado ainda.
    has_many :owned_groups, class_name: 'Group', foreign_key: :dm_user_id, dependent: :nullify
    has_many :schedules, through: :groups
    has_many :sheets, through: :characters
    has_many :sheet_klasses, through: :sheets
    has_many :campaign_notes

    belongs_to :role

    # DM: custom XP thresholds (levels 2–20) for progression UI; see DmProgressionSettingsMerge.
    # JSON shape: { "xp_thresholds" => { "2" => 300, "3" => 900, ... } }
    # Column added in db/migrate/20260422140000_add_progression_settings_to_users.rb
end
