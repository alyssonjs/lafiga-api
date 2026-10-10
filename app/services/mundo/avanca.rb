# frozen_string_literal: true

class Mundo
  # O AVANÇO do mundo (09/10; L0.4, plano B1): processa, em ordem de minuto, os eventos da agenda que já venceram até
  # o minuto de jogo de `agora`. Quem chama diz o agora (o processo `relogio` do L0.5, ou a leitura do mundo, que
  # alcança o presente ao abrir).
  #
  # - **Uma transação por evento:** o handler, o "processado" e os eventos que ele marca entram juntos, ou nada entra.
  # - **Trava por mundo, sem esperar:** um só avanço por mundo de cada vez. Quem chega com o mundo travado não espera
  #   (`pg_try_advisory_xact_lock`): sai `ocupado`, e o outro segue. O evento também é lido com `SKIP LOCKED`.
  # - **O minuto do evento é o agora do handler:** reprocessar dá o mesmo resultado (plano D11).
  # - **A falha para o mundo:** o evento que falha continua pendente, com a tentativa e o erro anotados, e o avanço para
  #   nele, para não processar o seguinte fora de ordem. O próximo avanço tenta de novo.
  module Avanca
    module_function

    # o namespace do advisory lock (o do combate, `Combat::ReorderService`, é 8_410)
    TRAVA = 8_420

    Resultado = Struct.new(:processados, :em_dia, :ocupado, :erro, keyword_init: true)

    def call(mundo, agora:, limite: 200)
      ate = Relogio.minuto(mundo, agora)
      processados = 0
      while processados < limite
        passo = um_evento(mundo, ate, agora)
        return Resultado.new(processados: processados, em_dia: false, ocupado: true) if passo == :ocupado
        return Resultado.new(processados: processados, em_dia: true, ocupado: false) if passo == :fim
        return Resultado.new(processados: processados, em_dia: false, ocupado: false, erro: passo.message) if passo.is_a?(Exception)

        processados += 1
      end
      Resultado.new(processados: processados, em_dia: !vencido?(mundo, ate), ocupado: false)
    end

    # :ok, :fim (nada vencido), :ocupado (outro avanço tem o mundo) ou a exceção do handler
    def um_evento(mundo, ate, agora)
      evento = nil
      Mundo.transaction(requires_new: true) do
        if !travou?(mundo)
          :ocupado
        elsif (evento = proximo(mundo, ate)).nil?
          :fim
        else
          processa!(evento, agora)
          :ok
        end
      end
    rescue StandardError => e
      anota_falha(evento, e) if evento
      e
    end

    # ⚠️ Fora do cache de consultas: com ele ligado (o executor do Rails, que embrulha a ronda do `relogio`), a segunda
    # pergunta "travou?" receberia a resposta guardada da primeira, sem ir ao banco
    def travou?(mundo)
      Mundo.uncached do
        ActiveModel::Type::Boolean.new.cast(
          Mundo.connection.select_value("SELECT pg_try_advisory_xact_lock(#{TRAVA}, #{mundo.id.to_i})"),
        )
      end
    end

    def proximo(mundo, ate)
      Evento.pendentes.where(mundo_id: mundo.id).where('minuto <= ?', ate).order(:minuto, :id)
            .lock('FOR UPDATE SKIP LOCKED').first
    end

    def vencido?(mundo, ate)
      Evento.pendentes.where(mundo_id: mundo.id).where('minuto <= ?', ate).exists?
    end

    def processa!(evento, agora)
      resultado = Agenda.handler(evento.tipo).call(evento, Relogio.momento(evento.minuto))
      evento.update!(processado_em: agora, resultado: resultado, erro: nil)
    end

    # fora da transação desfeita: a anotação da falha fica
    def anota_falha(evento, erro)
      Evento.where(id: evento.id).update_all(
        ['tentativas = tentativas + 1, erro = ?', "#{erro.class}: #{erro.message}"[0, 1000]],
      )
    end
  end
end
