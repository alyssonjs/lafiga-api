class User < ApplicationRecord
    # Campos que NUNCA devem aparecer em payloads de API. Usado pelos
    # controllers de auth/me/admin via `as_json(except: SENSITIVE_API_FIELDS)`.
    #
    # `password_digest`: hash bcrypt — vazava em /authenticate, /signup e /me
    # antes desta refatoração. Bcrypt resiste a brute force razoável, mas
    # expor o hash facilita ataques offline e quebra a expectativa básica
    # de "credenciais nunca saem do servidor".
    #
    # `password_changed_at` NÃO está aqui — é metadado público (front mostra
    # "última troca de senha em ..." na Profile page) e revelar a data não
    # introduz vetor.
    SENSITIVE_API_FIELDS = %i[password_digest].freeze

    has_secure_password

    validates :password, length: { minimum: 6 }, allow_nil: true
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

    before_save :mark_password_changed_at, if: :will_save_change_to_password_digest?

    # DM: custom XP thresholds (levels 2–20) for progression UI; see DmProgressionSettingsMerge.
    # JSON shape: { "xp_thresholds" => { "2" => 300, "3" => 900, ... } }
    # Column added in db/migrate/20260422140000_add_progression_settings_to_users.rb

    private

    def mark_password_changed_at
      self.password_changed_at = Time.current
    end
end
