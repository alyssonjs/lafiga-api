class CreateSheetKlass < ActiveRecord::Migration[6.0]
  def change
    create_table :sheet_klasses do |t|
      t.references :sheet, null: false, foreign_key: true
      t.references :klass, null: false, foreign_key: true
      t.references :sub_klass, foreign_key: true
      t.integer :level, limit: 2
    end

    add_index :sheet_klasses, [:sheet_id, :klass_id], unique: true, name: 'idx_sheet_klasses_unique_sheet_klass'
  end
end
