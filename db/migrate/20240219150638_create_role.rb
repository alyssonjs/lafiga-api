class CreateRole < ActiveRecord::Migration[6.0]
  def change
    create_table :roles do |t|
      t.string :name
      t.string :permissions, array: true, default: []
    end
  end
end
