class CreateUser < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.string :name
      t.string :username
      t.string :email
      t.string :phone
      t.string :password_digest
      t.references :role

      t.timestamps
    end
  end
end
