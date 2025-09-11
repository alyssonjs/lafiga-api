class AddRaceChoicesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :race_choices, :jsonb, default: {}, null: false
    add_index :sheets, :race_choices, using: :gin
  end
end
