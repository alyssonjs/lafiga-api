# Token do monstro pela BIBLIOTECA DE OBJETOS, como o companheiro (03/09).
#
# ⚠️ Coluna e não chave do `payload`: o payload é o STATBLOCK do SRD, e o
# desenho do token é escolha de apresentação desta mesa. Misturar os dois faria
# o re-import do Open5e (idempotente por `api_index`) sobrescrever o token que o
# Mestre escolheu.
class AddTokenMapAssetToMonsters < ActiveRecord::Migration[6.0]
  def change
    add_column :monsters, :token_map_asset_id, :bigint
    add_index :monsters, :token_map_asset_id
  end
end
