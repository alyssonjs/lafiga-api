class ExtendSubKlassesWithApiAndDetails < ActiveRecord::Migration[6.0]
  def change
    add_column :sub_klasses, :api_index, :string
    add_column :sub_klasses, :subclass_flavor, :string
    add_column :sub_klasses, :description, :text
    add_column :sub_klasses, :levels_json, :text
    add_index  :sub_klasses, :api_index, unique: true
  end
end

