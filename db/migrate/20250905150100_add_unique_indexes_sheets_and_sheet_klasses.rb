class AddUniqueIndexesSheetsAndSheetKlasses < ActiveRecord::Migration[6.0]
  def change
    add_index :sheets, :character_id, unique: true, name: 'idx_sheets_unique_character'
    add_index :sheet_klasses, [:sheet_id, :klass_id], unique: true, name: 'idx_sheet_klasses_unique_sheet_klass'
  end
end

