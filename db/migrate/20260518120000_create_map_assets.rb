# frozen_string_literal: true

# Fase 2.6 — Map Builder: biblioteca de assets enviados pelo DM.
#
# Espelha o conceito do Inkarnate (assets referenciados por id, não inline).
# A IMAGEM vai p/ ActiveStorage (`has_one_attached :image`), igual ao
# `Group#cover_image` — sem coluna binária aqui. Stamps/brush layers do
# mapa referenciam `MapAsset` por id; o JSONB do mapa continua enxuto.
#
# `kind`: 'texture' (pintável) | 'stamp' (objeto livre) | 'path' (via).
# `enabled`: DM pode esconder sem apagar (espelha o padrão `playable`).
class CreateMapAssets < ActiveRecord::Migration[6.0]
  def change
    create_table :map_assets do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.string :category, null: false, default: 'custom'
      t.string :color
      t.boolean :enabled, null: false, default: true
      t.references :user, foreign_key: true, null: true

      t.timestamps
    end

    add_index :map_assets, :kind
    add_index :map_assets, %i[kind enabled]
  end
end
