class CreateBattleMaps < ActiveRecord::Migration[6.0]
  # BattleMap = mapa tatico (grid + tokens + fog) usado em sessoes.
  # Modelo de propriedade hibrido decidido no plano end-to-end:
  #
  # - `user_id`         : owner / criador (sempre presente). Pode editar e deletar.
  # - `group_id`        : opcional. Quando presente, todos os members do grupo
  #                       enxergam o mapa em modo leitura (e o DM pode editar).
  #
  # Por que JSONB:
  # - `cells`  : [row][col] de TerrainType. Matriz 50x50 = 2500 strings curtas;
  #              JSONB permite atomic update do mapa inteiro num PATCH.
  # - `tokens` : array heterogeneo (color/chibi/custom) que evolui sem migration.
  # - `fog`    : nullable; matriz boolean cara para criar quando nem todo mapa
  #              usa fog of war.
  #
  # Por que TEXT em background_image_url:
  # - O front ja envia data URLs base64 comprimidos (~MBs); ActiveStorage seria
  #   ideal mas nao ha pipeline de upload de imagem em outro modulo do projeto
  #   ainda. Coluna TEXT segura ate ~1GB; consultas de listagem usam slim mode
  #   (sem este campo) via serializer.
  #
  # schema_version: prepara o terreno para a migration v1->v2 da Fase D6 (walls).
  def change
    create_table :battle_maps do |t|
      t.references :user, foreign_key: true, null: false
      t.references :group, foreign_key: true, null: true
      t.string :name, null: false
      t.integer :width, null: false
      t.integer :height, null: false
      t.integer :cell_size_px, null: false, default: 32
      t.jsonb :cells, null: false, default: []
      t.jsonb :tokens, null: false, default: []
      t.jsonb :fog
      t.text :background_image_url
      t.float :grid_opacity, default: 1.0
      t.integer :schema_version, null: false, default: 1
      t.timestamps
    end

    add_index :battle_maps, [:group_id, :updated_at]
    add_index :battle_maps, [:user_id, :updated_at]
    add_reference :schedules, :battle_map, foreign_key: true, index: true
  end
end
