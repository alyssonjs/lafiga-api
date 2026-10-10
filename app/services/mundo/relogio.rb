# frozen_string_literal: true

class Mundo
  # O RELÓGIO DO MUNDO, só a conta (09/10; L0.2, plano A19 e B1). A mesma conta está no front
  # (`front-lafiga/src/app/utils/relogioDoMundo.ts`), e os dois passam pelos mesmos casos
  # (`config/mundo/relogio_casos.json`).
  #
  # O calendário da vila: o dia tem 1440 minutos; a semana, 10 dias, um por Criador, na ordem da criação; a estação, 120
  # dias; o ano, 4 estações. O minuto 0 é a 0h do dia 1 da primavera do ano 1, dia de Ilahim. Os períodos: noite das 20h
  # às 4h, amanhecer das 4h às 6h, dia das 6h às 18h, anoitecer das 18h às 20h.
  #
  # Só inteiros (plano D11): o tempo real entra em milissegundos, e o tempo de jogo é contado em milissegundos de jogo,
  # para a reancoragem guardar a fração do minuto corrente.
  module Relogio
    module_function

    MS_NO_MINUTO = 60_000
    MINUTOS_NO_DIA = 1440
    DIAS_NA_SEMANA = 10
    DIAS_NA_ESTACAO = 120
    ESTACOES = %w[primavera verao outono inverno].freeze
    DIAS_NO_ANO = DIAS_NA_ESTACAO * ESTACOES.size
    CRIADORES = ['Ilahim', "M'avi", 'Vaëham', 'Oorun', 'Aëlar', 'Naali', 'Arendal', 'Rhönar', 'Rhaaz', 'Kaländriz'].freeze
    # [o minuto do dia em que começa, o período]
    PERIODOS = [[0, 'noite'], [240, 'amanhecer'], [360, 'dia'], [1080, 'anoitecer'], [1200, 'noite']].freeze

    # A âncora sem banco (os casos, a agenda); o `Mundo` responde aos mesmos campos.
    Ancora = Struct.new(:epoca_em, :minuto_na_epoca, :fator, :pausado_desde, keyword_init: true)

    # O minuto de jogo em `agora`. Pausado, o relógio para em `pausado_desde`; um agora antes da época não volta.
    def minuto(ancora, agora)
      jogo_ms(ancora, agora) / MS_NO_MINUTO
    end

    def momento(minuto)
      dia, do_dia = minuto.divmod(MINUTOS_NO_DIA)
      hora, minuto_da_hora = do_dia.divmod(60)
      {
        minuto: minuto,
        dia: dia,
        hora: hora,
        minuto_da_hora: minuto_da_hora,
        dia_da_semana: dia % DIAS_NA_SEMANA,
        criador: CRIADORES[dia % DIAS_NA_SEMANA],
        periodo: PERIODOS.reverse_each.find { |inicio, _| do_dia >= inicio }.last,
        estacao: ESTACOES[(dia / DIAS_NA_ESTACAO) % ESTACOES.size],
        dia_da_estacao: (dia % DIAS_NA_ESTACAO) + 1,
        ano: (dia / DIAS_NO_ANO) + 1,
      }
    end

    # A âncora nova para mudar o `fator` ou pausar/despausar em `agora`, SEM SALTO: o minuto continua o mesmo, e a fração
    # do minuto corrente passa para a velocidade nova (a época recua o que já tinha andado dele). Pausar o que já está
    # pausado guarda o instante da pausa. Devolve uma `Ancora`.
    def reancora(ancora, agora, fator: nil, pausar: nil)
      fator ||= ancora.fator
      raise ArgumentError, "fator inválido: #{fator.inspect}" unless fator.is_a?(Integer) && fator.positive?

      minuto, fracao = jogo_ms(ancora, agora).divmod(MS_NO_MINUTO)
      volta = fracao / fator
      pausado = pausar.nil? ? !ancora.pausado_desde.nil? : pausar
      desde = pausado ? ms(ancora.pausado_desde || agora) : nil
      Ancora.new(
        epoca_em: hora_em_ms((desde || ms(agora)) - volta),
        minuto_na_epoca: minuto,
        fator: fator,
        pausado_desde: desde && hora_em_ms(desde),
      )
    end

    def jogo_ms(ancora, agora)
      decorrido = [ms(ancora.pausado_desde || agora) - ms(ancora.epoca_em), 0].max
      (ancora.minuto_na_epoca * MS_NO_MINUTO) + (decorrido * ancora.fator)
    end

    # Time ↔ milissegundos inteiros (`to_r` é exato; nada de Float)
    def ms(tempo)
      (tempo.to_r * 1000).floor
    end

    def hora_em_ms(total)
      Time.at(total / 1000, total % 1000, :millisecond).utc
    end
  end
end
