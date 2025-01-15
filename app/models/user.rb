class User < ApplicationRecord
    has_secure_password

    validates :email, presence: true, uniqueness: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :username, presence: true, uniqueness: true
    validates :role_id, presence: true

    has_many :characters
    has_many :groups, through: :characters
    has_many :schedules, through: :groups
    
    belongs_to :role

end