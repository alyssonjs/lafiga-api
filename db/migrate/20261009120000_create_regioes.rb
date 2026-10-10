# frozen_string_literal: true

# As REGIÕES de Lafiga (09/10; L1.1 do roadmap da vila, plano A14 e B3). A linha é a identidade, para as chaves
# estrangeiras (a campanha agora; a vila e o mapa depois); a ficha (biomas, recursos, fauna, CDs, a campanha) mora em
# `config/mundo/regioes/<chave>.yml` e é lida por `Regioes::Ficha`. No MVP há uma só: Argoba, em Zandria.
class CreateRegioes < ActiveRecord::Migration[6.0]
  def change
    create_table :regioes do |t|
      t.string :chave, null: false, index: { unique: true }
      t.string :nome, null: false
      t.string :reino, null: false
      t.timestamps
    end
  end
end
