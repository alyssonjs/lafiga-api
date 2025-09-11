class Feature < ApplicationRecord
  # Associations
  has_and_belongs_to_many :class_levels
  has_and_belongs_to_many :sub_klass_levels

  # Validations
  validates :api_index, :name, presence: true

  # Categories help distinguish origin/use for UI/logic
  # 0: class_feature (default), 1: subclass_feature, 2: racial_trait, 3: feat
  enum category: { class_feature: 0, subclass_feature: 1, racial_trait: 2, feat: 3 }
end
