class CreateKlass < ActiveRecord::Migration[6.0]
  def change
    create_table :klasses do |t|
      t.string :name
    end
  end
end
