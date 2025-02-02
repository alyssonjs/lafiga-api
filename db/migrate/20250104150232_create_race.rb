class CreateRace < ActiveRecord::Migration[6.0]
  def change
    create_table :races do |t|
      t.string :name

      t.timestamps
    end
  end
end
