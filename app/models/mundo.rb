# frozen_string_literal: true

# O MUNDO de um grupo (L0.2; plano B1): o relógio da vila. Guarda só a âncora; a hora, o dia, o Criador do dia, o
# período e a estação saem de conta (`Mundo::Relogio`).
#
# Quem chama diz o AGORA: o relógio não lê a hora sozinho, para que a agenda (L0.4) possa usar o minuto do evento como
# "agora" e reprocessar dê o mesmo resultado.
class Mundo < ApplicationRecord
  belongs_to :group
  # a agenda (L0.4): o que vai acontecer, por minuto de jogo
  has_many :eventos, class_name: 'Mundo::Evento', dependent: :delete_all
  # a campanha regional que corre neste mundo (L1.1): A Retomada de Argoba
  has_many :campanhas, dependent: :destroy

  validates :group_id, uniqueness: true
  validates :epoca_em, presence: true
  validates :minuto_na_epoca, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :fator, numericality: { only_integer: true, greater_than: 0 }

  def minuto_em(agora)
    Relogio.minuto(self, agora)
  end

  def momento_em(agora)
    Relogio.momento(minuto_em(agora))
  end

  # Muda o fator, pausa ou despausa sem salto no minuto (ver `Relogio.reancora`).
  def reancora!(agora:, fator: nil, pausar: nil)
    update!(Relogio.reancora(self, agora, fator: fator, pausar: pausar).to_h)
  end

  # Um SALTO de propósito: avança `minutos` de jogo, guardando a fração do minuto corrente. Só o `/dev` usa.
  def avanca!(agora:, minutos:)
    nova = Relogio.reancora(self, agora)
    update!(nova.to_h.merge(minuto_na_epoca: nova.minuto_na_epoca + minutos))
  end

  # A âncora como o front a lê (`AncoraDaApi` em `relogioDoMundo.ts`): as horas em ISO 8601, com milissegundos.
  def para_api
    {
      id: id,
      group_id: group_id,
      epoca_em: epoca_em.utc.iso8601(3),
      minuto_na_epoca: minuto_na_epoca,
      fator: fator,
      pausado_desde: pausado_desde&.utc&.iso8601(3),
    }
  end
end
