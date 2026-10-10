# frozen_string_literal: true

# O MUNDO de cada grupo (09/10; L0.2 do roadmap da vila, plano B1): o relógio que anda sozinho, na mesma velocidade com
# ou sem gente online. A hora não é gravada a cada minuto: ela sai de conta (`Mundo::Relogio`) a partir da âncora.
#
# Campos:
#   - `epoca_em`: o instante real em que o relógio marcava `minuto_na_epoca`;
#   - `minuto_na_epoca`: o minuto de jogo nesse instante (o minuto 0 é a 0h do dia 1 da primavera do ano 1);
#   - `fator`: minutos de jogo por minuto real (40 = o dia de 36 min, a estação de 3 dias reais);
#   - `pausado_desde`: o relógio parado (manutenção, o Mestre). Nulo = andando.
#
# Mudar o fator ou pausar REANCORA (`Mundo#reancora!`): a época passa a ser o agora, sem salto no minuto.
#
# O calendário da vila é SEPARADO do da campanha (decisão de 09/10): `groups.day`/`season` continuam sendo o calendário
# que o Mestre anda à mão; este é o da vila.
class CreateMundos < ActiveRecord::Migration[6.0]
  def change
    create_table :mundos do |t|
      t.references :group, null: false, foreign_key: true, index: { unique: true }
      t.datetime :epoca_em, null: false
      t.bigint :minuto_na_epoca, null: false, default: 0
      t.integer :fator, null: false, default: 40
      t.datetime :pausado_desde
      t.timestamps
    end
  end
end
