# frozen_string_literal: true

class Mundo
  # Um EVENTO da agenda do mundo (L0.4; tabela `mundo_agenda`). Marca-se pelo `Mundo::Agenda::Marca` e processa-se pelo
  # `Mundo::Avanca`, nunca direto.
  class Evento < ApplicationRecord
    self.table_name = 'mundo_agenda'

    belongs_to :mundo

    scope :pendentes, -> { where(processado_em: nil) }

    validates :tipo, :chave, presence: true
    validates :minuto, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
