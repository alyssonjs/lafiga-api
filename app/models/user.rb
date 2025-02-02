class User < ApplicationRecord
    has_secure_password

    validates :email, presence: true, uniqueness: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :username, presence: true, uniqueness: true
    validates :role_id, presence: true

    has_many :characters
    has_many :groups, through: :characters
    has_many :schedules, through: :groups
    has_many :sheets, through: :characters
    has_many :sheet_klasses, through: :sheets
    
    belongs_to :role
end