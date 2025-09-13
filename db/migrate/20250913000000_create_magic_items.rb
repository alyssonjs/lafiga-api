class CreateMagicItems < ActiveRecord::Migration[6.0]
  def change
    create_table :magic_items do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :rarity
      t.string  :category
      t.string  :sub_category
      t.boolean :requires_attunement, null: false, default: false
      t.string  :attunement_note
      t.decimal :weight_kg, precision: 8, scale: 2
      t.decimal :value_gp,  precision: 10, scale: 2
      t.string  :source
      t.boolean :cursed, default: false
      t.text    :curse_text
      t.integer :charges
      t.string  :recharge
      t.jsonb   :bonuses, default: {}
      t.jsonb   :properties, default: {}
      t.text    :description
      t.text    :tags, array: true, default: []
      t.timestamps
    end

    add_index :magic_items, :slug, unique: true
    add_index :magic_items, :name
    add_index :magic_items, :rarity
    add_index :magic_items, :category
    add_index :magic_items, :tags, using: :gin
  end
end

