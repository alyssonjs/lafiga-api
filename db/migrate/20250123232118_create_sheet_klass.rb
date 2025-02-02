class CreateSheetKlass < ActiveRecord::Migration[6.0]
  def change
    create_table :sheet_klasses do |t|
      t.references :sheet, foreign_key: true, null: false
      t.references :klass, foreign_key: true, null: false
      t.references :sub_klass, foreign_key: true, null: true
      t.integer :level, limit: 2
    end
  end
end
