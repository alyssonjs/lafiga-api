class AddGroupIdToCharacters < ActiveRecord::Migration[6.0]
  def change
    add_reference :characters, :group, foreign_key: true, null: true
  end
end