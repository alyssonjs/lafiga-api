class CreateSubKlass < ActiveRecord::Migration[6.0]
  def change
    create_table :sub_klasses do |t|
      t.string :name
      t.references :klass, foreign_key: true, null: false
    end
  end
end
