class SubKlass < ApplicationRecord
  validates :name, :klass_id, presence: true

  belongs_to :klass
  has_many :sub_klass_levels, dependent: :destroy
  has_many :features, through: :sub_klass_levels
end
