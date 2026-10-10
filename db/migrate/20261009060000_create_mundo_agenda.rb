# frozen_string_literal: true

# A AGENDA do mundo (09/10; L0.4, plano B1): o que vai acontecer, e em que minuto de jogo. O mundo não simula minuto a
# minuto: quem avança (`Mundo::Avanca`) processa, em ordem, os eventos que já venceram, um por transação.
#
# Campos:
#   - `minuto`: o minuto de jogo em que o evento vence. É o "agora" do handler (nunca o relógio da máquina);
#   - `tipo`: quem trata (`Mundo::Agenda::TIPOS`);
#   - `chave`: a identidade do evento no mundo. Marcar de novo a mesma chave não duplica (`Mundo::Agenda::Marca`);
#   - `dados`: o que o handler precisa;
#   - `processado_em`/`resultado`: o instante real em que foi processado e o que ele deu;
#   - `tentativas`/`erro`: a última falha. O evento que falha continua pendente, e o mundo para nele até dar certo, para
#     não processar fora de ordem.
#
# Índices:
#   - `[mundo_id, chave]` único: a idempotência;
#   - `[mundo_id, minuto, id]` só dos pendentes: a leitura do avanço é "o próximo vencido deste mundo".
class CreateMundoAgenda < ActiveRecord::Migration[6.0]
  def change
    create_table :mundo_agenda do |t|
      t.references :mundo, null: false, foreign_key: true, index: false
      t.bigint :minuto, null: false
      t.string :tipo, null: false
      t.string :chave, null: false
      t.jsonb :dados, null: false, default: {}
      t.datetime :processado_em
      t.jsonb :resultado
      t.integer :tentativas, null: false, default: 0
      t.text :erro
      t.timestamps
    end
    add_index :mundo_agenda, %i[mundo_id chave], unique: true
    add_index :mundo_agenda, %i[mundo_id minuto id], where: 'processado_em IS NULL', name: 'index_mundo_agenda_pendentes'
  end
end
