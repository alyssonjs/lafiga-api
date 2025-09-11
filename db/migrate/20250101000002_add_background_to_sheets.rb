class AddBackgroundToSheets < ActiveRecord::Migration[6.0]
  def change
    add_reference :sheets, :background, null: true, foreign_key: true
    add_column :sheets, :background_key, :string
    add_index :sheets, :background_id
    add_index :sheets, :background_key
  end
end
