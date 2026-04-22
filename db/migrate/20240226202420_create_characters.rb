class CreateCharacters < ActiveRecord::Migration[6.0]
  def change
    create_table :characters do |t|
      t.string :name
      t.text :background
      t.references :user, null: false, foreign_key: true
      t.references :group, null: true, foreign_key: true
      t.integer :status, default: 0, null: false
      t.integer :current_step
      t.jsonb :draft_data, default: {}

      t.timestamps
    end
  end
end
