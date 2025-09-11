class CharactersFeature < ApplicationRecord
  self.table_name = 'characters_features'

  belongs_to :character
  belongs_to :feature

  validates :character_id, :feature_id, presence: true
  validates :feature_id, uniqueness: { scope: :character_id }
end

