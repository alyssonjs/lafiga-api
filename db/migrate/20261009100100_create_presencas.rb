# frozen_string_literal: true

# Onde cada personagem ESTÁ (09/10; L0.8, plano B3): um lugar por personagem. O índice único em `character_id` é a
# regra: entrar numa mesa tira o personagem de onde ele estava (`Presencas::Entra`), e ele nunca fica em dois lugares
# (a sessão de campanha e a mesa da vila, por exemplo).
#
# Campos:
#   - `schedule_id`: a mesa (de qualquer modo: campanha, vila, missão, encontro);
#   - `battle_map_id`: o mapa dentro dela, quando há (os portais do L5.2 mudam este);
#   - `pilha`: a pilha de retorno dos portais (L5.2): de onde ele veio, para voltar;
#   - `batimento_em`: o último sinal de vida. Quem fica sem batimento sai (quem cuida disso é o canal da vila, L1.8).
class CreatePresencas < ActiveRecord::Migration[6.0]
  def change
    create_table :presencas do |t|
      t.references :character, null: false, foreign_key: true, index: { unique: true }
      t.references :schedule, null: false, foreign_key: true
      t.references :battle_map, foreign_key: true
      t.jsonb :pilha, null: false, default: []
      t.datetime :batimento_em, null: false
      t.timestamps
    end
  end
end
