class AddClassChoicesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :class_choices, :jsonb, default: {}, null: false
    add_index :sheets, :class_choices, using: :gin
  end
end
