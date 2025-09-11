class AddSubclassLevelToKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :klasses, :subclass_level, :integer
  end
end

