# frozen_string_literal: true

# Metadados do ASSET vindos do catálogo de origem (hoje: a sombra por stamp do
# Inkarnate — 'none' p/ arte com sombra pintada, receita custom p/ alguns).
# jsonb de propósito: o próximo metadado (flip? tint?) entra sem migration.
class AddMetaToMapAssets < ActiveRecord::Migration[6.0]
  def change
    add_column :map_assets, :meta, :jsonb, null: false, default: {}
  end
end
