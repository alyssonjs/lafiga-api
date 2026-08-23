class AddCartsToGroups < ActiveRecord::Migration[6.0]
  # Depósito móvel do GRUPO (carroça, carruagem, vagão…). Vive aqui e não numa
  # ficha porque é compartilhado: `Group` não tinha inventário nenhum.
  #
  # O ITEM continua na ficha do dono — a carroça guarda só uma referência. É
  # isso que dá "de quem é cada item" de graça, sem transferir posse.
  #
  # Shape: [{ id, name, item_index, mounts: [{ sheet_id, companion_id }] }]
  # `mounts` são os animais atrelados: pela regra do PHB a capacidade é deles,
  # não do veículo.
  def change
    add_column :groups, :carts, :jsonb, default: [], null: false
  end
end
