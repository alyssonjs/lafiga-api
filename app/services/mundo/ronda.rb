# frozen_string_literal: true

class Mundo
  # UMA RONDA do processo `relogio` (09/10; L0.5, plano B1): avança todos os mundos que têm evento vencido em `agora`,
  # cada um pelo `Avanca` (que tem a trava por mundo).
  #
  # - **Trava global:** duas rondas não correm ao mesmo tempo (o laço do serviço e o cron de reserva). É de sessão
  #   (`pg_try_advisory_lock`), porque a ronda não é uma transação: cada evento tem a sua. Quem não pega a trava sai
  #   sem rodar.
  # - **Parados:** devolve os eventos que já falharam `AVISO_APOS` vezes e seguram o mundo (L0.4), para quem roda a
  #   ronda avisar.
  module Ronda
    module_function

    # o namespace do advisory lock global (o do mundo, `Avanca::TRAVA`, é 8_420)
    TRAVA_GLOBAL = 8_421
    AVISO_APOS = 3

    Resultado = Struct.new(:rodou, :mundos, :processados, :ocupados, :erros, :parados, keyword_init: true)

    def call(agora:, limite_por_mundo: 200)
      return Resultado.new(rodou: false, mundos: 0, processados: 0, ocupados: 0, erros: [], parados: []) unless trava_global?

      begin
        avancos = mundos_vencidos(agora).map { |m| [m, Avanca.call(m, agora: agora, limite: limite_por_mundo)] }
        Resultado.new(
          rodou: true,
          mundos: avancos.size,
          processados: avancos.sum { |_, r| r.processados },
          ocupados: avancos.count { |_, r| r.ocupado },
          erros: avancos.filter_map { |m, r| [m.id, r.erro] if r.erro },
          parados: parados,
        )
      ensure
        solta_trava_global
      end
    end

    # os mundos cujo evento pendente mais cedo já venceu no minuto de jogo de cada um
    def mundos_vencidos(agora)
      proximos = Evento.pendentes.group(:mundo_id).minimum(:minuto)
      Mundo.where(id: proximos.keys).order(:id).select { |m| proximos[m.id] <= Relogio.minuto(m, agora) }
    end

    # [mundo_id, evento_id, tipo, tentativas, erro] dos eventos que seguram o seu mundo
    def parados
      Evento.pendentes.where('tentativas >= ?', AVISO_APOS).order(:mundo_id, :minuto)
            .pluck(:mundo_id, :id, :tipo, :tentativas, :erro)
    end

    # ⚠️ As duas fora do cache de consultas (ver `Avanca.travou?`): cacheadas, a trava respondia o que respondeu antes e
    # o "soltar" não chegava ao banco
    def trava_global?
      Mundo.uncached do
        ActiveModel::Type::Boolean.new.cast(Mundo.connection.select_value("SELECT pg_try_advisory_lock(#{TRAVA_GLOBAL})"))
      end
    end

    def solta_trava_global
      Mundo.uncached { Mundo.connection.select_value("SELECT pg_advisory_unlock(#{TRAVA_GLOBAL})") }
    end
  end
end
