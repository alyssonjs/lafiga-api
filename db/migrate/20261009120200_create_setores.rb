# frozen_string_literal: true

# Os SETORES de uma campanha (09/10; L1.1, plano B3 e I6; GDD §91): a corrente assentamento → floresta → Búzios →
# estrada → posto → periferia → distrito, na `ordem`.
#
# Campos:
#   - `tipo`: assentamento, selvagem, vila_aliada, estrada, posto, periferia, distrito;
#   - `bioma`: o do vocabulário de bioma (`Regiao::BIOMAS`);
#   - `estado`: perdido, disputado ou recuperado (o posto e a incursão mudam, L8);
#   - `territorio`: comum, infestado ou amaldiçoado, que dá a CD do acampamento (plano A15);
#   - `pressao_selvagem` e `influencia` (a do Colonizador): as duas réguas da I6, de 0 a 100.
class CreateSetores < ActiveRecord::Migration[6.0]
  def change
    create_table :setores do |t|
      t.references :campanha, null: false, foreign_key: true, index: false # os índices de (campanha_id, …) servem
      t.string :chave, null: false
      t.string :nome, null: false
      t.string :tipo, null: false
      t.string :bioma, null: false
      t.string :estado, null: false
      t.string :territorio, null: false
      t.integer :pressao_selvagem, null: false, default: 0
      t.integer :influencia, null: false, default: 0
      t.integer :ordem, null: false
      t.timestamps
    end
    add_index :setores, %i[campanha_id chave], unique: true
    add_index :setores, %i[campanha_id ordem], unique: true
  end
end
