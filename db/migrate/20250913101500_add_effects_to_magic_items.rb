class AddEffectsToMagicItems < ActiveRecord::Migration[6.0]
  def change
    add_column :magic_items, :effects, :jsonb, default: []
  end
end

