class CreateItems < ActiveRecord::Migration[6.0]
  def change
    create_table :items do |t|
      t.string  :api_index, null: false
      t.string  :name, null: false
      t.string  :kind, null: false              # weapon, armor, shield, ammunition, gear, tool, book, consumable, magic_item
      t.string  :category                       # weapon: simple|martial; armor: light|medium|heavy; etc.
      t.decimal :value_gp, precision: 10, scale: 2
      t.decimal :weight_kg, precision: 8, scale: 2
      t.string  :rarity                          # magic items
      t.boolean :requires_attunement, default: false, null: false # magic items
      t.string  :attunement_note                 # magic items
      t.string  :sub_category                    # magic items / weapons subtype
      t.boolean :cursed, default: false          # magic items
      t.text    :curse_text                      # magic items
      t.integer :charges                         # magic items
      t.string  :recharge                        # magic items
      t.string  :source                          # magic items
      t.text    :description                     # magic items
      t.text    :tags, array: true, default: []  # magic items
      t.jsonb   :props, default: {}
      t.timestamps
    end
    add_index :items, :api_index, unique: true
    add_index :items, :kind
    add_index :items, :category
    add_index :items, :rarity
    add_index :items, :tags, using: :gin
    add_index :items, :props, using: :gin
  end
end


