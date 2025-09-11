class ClassLevel < ApplicationRecord
  belongs_to :klass
  has_and_belongs_to_many :features
  has_one :spellcasting, dependent: :destroy
end
