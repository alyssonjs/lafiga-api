# frozen_string_literal: true

# A CAMPANHA REGIONAL de um mundo (09/10; L1.1, plano B3, I1 e I5; GDD §86): "A Retomada de Argoba", com a ameaça (o
# Colonizador) e a etapa do arco (assentamento → postos → periferia → distritos → cidade). É do mundo, e não do grupo,
# porque anda pelo relógio dele: a influência da ameaça sobe com o tempo (L4.1).
#
# `ameaca` é a chave da ameaça na ficha; as facções ganham tabela no L4.1.
class CreateCampanhas < ActiveRecord::Migration[6.0]
  def change
    create_table :campanhas do |t|
      t.references :mundo, null: false, foreign_key: true, index: false # o índice de (mundo_id, chave) serve
      t.references :regiao, null: false, foreign_key: { to_table: :regioes }
      t.string :chave, null: false
      t.string :nome, null: false
      t.string :ameaca, null: false
      t.string :etapa, null: false
      t.timestamps
    end
    add_index :campanhas, %i[mundo_id chave], unique: true
  end
end
