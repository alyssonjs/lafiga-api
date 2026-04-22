class DiaryEntry < ApplicationRecord
  belongs_to :character
  belongs_to :schedule, optional: true

  validates :title, length: { maximum: 200 }
  validates :font_family, presence: true
  validates :font_size, numericality: { only_integer: true, greater_than_or_equal_to: 8, less_than_or_equal_to: 72 }
  validates :text_color, presence: true
  validates :page_color, presence: true

  scope :recent_first, -> { order(updated_at: :desc) }
end
