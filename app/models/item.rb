class Item < ApplicationRecord
  enum kind: {
    weapon: 'weapon', armor: 'armor', shield: 'shield', ammunition: 'ammunition',
    gear: 'gear', tool: 'tool', book: 'book', consumable: 'consumable', magic_item: 'magic_item'
  }

  validates :api_index, presence: true, uniqueness: true
  validates :name, presence: true
  validates :kind, presence: true
end


