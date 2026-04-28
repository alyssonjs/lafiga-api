# frozen_string_literal: true

class AddRulesAndVariantsToBackgrounds < ActiveRecord::Migration[6.0]
  def change
    add_column :backgrounds, :rules, :jsonb, null: false, default: {}
    add_column :backgrounds, :parent_api_index, :string
    add_column :backgrounds, :published, :boolean, null: false, default: true

    add_index :backgrounds, :parent_api_index
    add_index :backgrounds, :published
  end
end
