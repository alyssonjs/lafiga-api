class AddMetadataToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :metadata, :jsonb, default: {}, null: false
  end
end

