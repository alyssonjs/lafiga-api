class AddSummariesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :race_summary, :jsonb, default: {}, null: false
    add_column :sheets, :class_summary, :jsonb, default: {}, null: false
    add_column :sheets, :background_summary, :jsonb, default: {}, null: false
    add_column :sheets, :features_by_level, :jsonb, default: {}, null: false
    
    add_index :sheets, :race_summary, using: :gin
    add_index :sheets, :class_summary, using: :gin
    add_index :sheets, :background_summary, using: :gin
    add_index :sheets, :features_by_level, using: :gin
  end
end
