# frozen_string_literal: true

class Mundo
  module Agenda
    # Um EVENTO SISTÊMICO na agenda (L0.7): rola o evento do catálogo (`Mundo::Eventos`) com os fatores que quem marcou
    # mediu no estado do mundo. A chave da rolagem é a do evento da agenda: reprocessar devolve a mesma rolagem, e o
    # mesmo resultado (plano D11). Quem vai marcar estes eventos, medindo a vila, é o pulso (L2.9).
    #
    # `dados`: `evento` (a chave no catálogo, ex.: `doenca`) e `fatores` (os ativos: lista ou chave → vezes).
    module Sistemico
      module_function

      def call(evento, _momento)
        Eventos.rola(
          evento.dados['evento'],
          ativos: evento.dados['fatores'] || [],
          chave: "mundo:#{evento.mundo_id}:agenda:#{evento.chave}",
          contexto: { 'mundo_id' => evento.mundo_id, 'agenda_id' => evento.id, 'minuto' => evento.minuto },
        )
      end
    end
  end
end
