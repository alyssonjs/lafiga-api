class AddRaceBonusesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :race_bonuses_applied, :jsonb, default: {}, null: false
    add_index :sheets, :race_bonuses_applied, using: :gin
  end
end
