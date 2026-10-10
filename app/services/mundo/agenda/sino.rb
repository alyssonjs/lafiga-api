# frozen_string_literal: true

class Mundo
  module Agenda
    # O SINO DAS HORAS (L0.4): o primeiro tipo de evento, para pôr a agenda à prova antes dos eventos de jogo (o clima,
    # as tarefas, a virada do dia). Toca no minuto do evento, guarda a hora, o dia e o Criador do dia, e marca o
    # próximo toque.
    #
    # `dados`: `a_cada` (minutos até o próximo toque; sem ele, toca uma vez) e `ate` (o último minuto em que toca).
    module Sino
      module_function

      def call(evento, momento)
        a_cada = evento.dados['a_cada'].to_i
        proximo = evento.minuto + a_cada
        ate = evento.dados['ate']
        if a_cada.positive? && (ate.nil? || proximo <= ate.to_i)
          Marca.call(evento.mundo, minuto: proximo, tipo: 'sino', chave: "sino:#{proximo}", dados: evento.dados)
        end
        { 'hora' => momento[:hora], 'dia' => momento[:dia], 'criador' => momento[:criador] }
      end
    end
  end
end
