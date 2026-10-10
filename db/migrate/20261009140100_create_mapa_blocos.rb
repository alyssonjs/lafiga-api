# frozen_string_literal: true

# Os BLOCOS do mapa da vila (09/10; L1.2, plano B3 e B8). Cada um guarda 40×40 células (o lado mora em
# `config/mundo/mapa_blocos.json`, o mesmo arquivo que o front confere); os da última coluna e da última linha podem
# ser menores.
#
# Campos:
#   - `bc`, `bl`: a coluna e a linha do bloco (não `by`, que é palavra reservada do SQL);
#   - `terreno`: `{ camadas: { "<terreno>": "<base64>" } }`, uma camada de bits por terreno do LPC, nos VÉRTICES do
#     bloco ((colunas + 1) × (linhas + 1), por linha; a borda repete a do vizinho). A ordem de desenho é a do formato;
#   - `objetos`: os objetos ESPARSOS que moram no bloco (árvore, casa, pedra, carimbo, piso), cada um no bloco do pé;
#   - `versao`: sobe a cada mudança; o `bloco_mudou` leva a nova, e o cliente recarrega só aquele bloco.
class CreateMapaBlocos < ActiveRecord::Migration[6.0]
  def change
    create_table :mapa_blocos do |t|
      t.references :battle_map, null: false, foreign_key: true, index: false # o índice de (battle_map_id, bc, bl) serve
      t.integer :bc, null: false
      t.integer :bl, null: false
      t.jsonb :terreno, null: false, default: {}
      t.jsonb :objetos, null: false, default: []
      t.integer :versao, null: false, default: 1
      t.timestamps
    end
    add_index :mapa_blocos, %i[battle_map_id bc bl], unique: true
  end
end
