class SubKlass < ApplicationRecord
  validates :name, :klass_id, presence: true

  belongs_to :klass
end