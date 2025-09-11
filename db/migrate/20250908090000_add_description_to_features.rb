class AddDescriptionToFeatures < ActiveRecord::Migration[6.0]
  def change
    add_column :features, :description, :text
  end
end
