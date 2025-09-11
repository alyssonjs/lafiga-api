class AddDndFieldsToKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :klasses, :api_index, :string
    add_index :klasses, :api_index, unique: true
    add_column :klasses, :hit_die, :integer
    add_column :klasses, :spellcasting_ability, :string
  end
end
