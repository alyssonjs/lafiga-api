class CreateSheetFeats < ActiveRecord::Migration[6.0]
  def change
    create_table :sheet_feats do |t|
      t.references :sheet, null: false, foreign_key: true
      t.references :feat, null: false, foreign_key: true
      t.integer :level_gained, null: false
      t.text :choices # JSON string for feat choices (e.g., which ability score for Resilient)
      t.timestamps
    end

    add_index :sheet_feats, [:sheet_id, :feat_id], unique: true
    add_index :sheet_feats, :level_gained
  end
end
