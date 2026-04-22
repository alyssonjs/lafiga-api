class CreateSheetItems < ActiveRecord::Migration[6.0]
  def change
    create_table :sheet_items do |t|
      t.references :sheet, null: false, foreign_key: true
      t.string :item_index
      t.string :item_name, null: false
      t.string :category
      t.integer :quantity, null: false, default: 1
      t.boolean :equipped, null: false, default: false
      t.string :slot
      t.string :source
      t.jsonb :props_json
      t.text :notes
      t.references :item, foreign_key: true

      t.timestamps
    end

    add_index :sheet_items, [:sheet_id, :item_index]
  end
end
