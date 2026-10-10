# frozen_string_literal: true

class Mundo
  module Agenda
    # MARCA um evento na agenda do mundo, SEM DUPLICAR (L0.4): a `chave` é a identidade do evento no mundo. Marcar de
    # novo a mesma chave devolve o evento que já existe, como está (o minuto e os dados da primeira vez). É o que deixa
    # reprocessar um handler, ou repetir uma requisição, sem criar eventos em dobro.
    module Marca
      module_function

      def call(mundo, minuto:, tipo:, chave:, dados: {})
        raise ArgumentError, "minuto inválido: #{minuto.inspect}" unless minuto.is_a?(Integer) && minuto >= 0

        Evento.create_or_find_by!(mundo_id: mundo.id, chave: chave.to_s) do |e|
          e.minuto = minuto
          e.tipo = tipo.to_s
          e.dados = dados
        end
      end
    end
  end
end
