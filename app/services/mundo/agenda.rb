# frozen_string_literal: true

class Mundo
  # A AGENDA do mundo (09/10; L0.4, plano B1): quem trata cada tipo de evento.
  #
  # Um handler é um módulo com `call(evento, momento)`. O `momento` é o do MINUTO DO EVENTO (`Relogio.momento`): é o
  # "agora" do jogo, e o handler nunca lê o relógio da máquina nem sorteia por conta própria (plano D11; o dado vem
  # do `Dados::Fonte`, L0.6). Ele devolve o resultado (um Hash, gravado no evento) e pode marcar os eventos seguintes
  # pelo `Agenda::Marca`, na mesma transação.
  module Agenda
    # o nome da constante, e não ela, para o autoload achar o handler na hora
    TIPOS = {
      'sino' => 'Mundo::Agenda::Sino',
      'sistemico' => 'Mundo::Agenda::Sistemico',
    }.freeze

    def self.handler(tipo)
      nome = TIPOS[tipo.to_s]
      raise ArgumentError, "tipo de evento desconhecido: #{tipo.inspect}" unless nome

      nome.constantize
    end
  end
end
