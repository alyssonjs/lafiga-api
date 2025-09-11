class AddCurrentLevelToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :current_level, :integer, default: 1, null: false
    add_index :sheets, :current_level
  end
end
