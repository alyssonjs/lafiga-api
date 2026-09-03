# O token do companheiro pode vir da BIBLIOTECA DE OBJETOS (1962 assets em
# 03/09) em vez de um PNG novo a cada criatura.
#
# ⚠️ Guarda a REFERÊNCIA, não uma cópia do blob — a mesma razão que o mapa já
# usa para os stamps: "referenciam o id deste registro (nunca embutem a
# imagem)". Copiar duplicaria 1962 imagens potenciais e faria o token velho
# mentir quando o Mestre corrigisse o asset.
class AddTokenMapAssetToCompanionTemplates < ActiveRecord::Migration[6.0]
  def change
    add_column :companion_templates, :token_map_asset_id, :bigint
    add_index :companion_templates, :token_map_asset_id
  end
end
