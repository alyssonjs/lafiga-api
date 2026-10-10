# frozen_string_literal: true

class Mundo
  # A ESTAÇÃO CONTÍNUA (09/10; a E1 de `jogo/composicao-do-mapa.md`): o ano visto dia a dia, para a estação mudar aos
  # poucos e nunca de uma vez. A mesma conta está no front (`front-lafiga/src/app/utils/estacaoDoMundo.ts`), e os dois
  # passam pelos mesmos casos (`config/mundo/estacoes_casos.json`).
  #
  # - O DEGRAU é o dia: o estado muda uma vez por dia de jogo, nunca no meio dele.
  # - A PONTE entre duas estações tem 40 dias: os últimos 30 de uma e os primeiros 10 da seguinte (decidido em 09/10, a
  #   calibrar na E0). Fora dela, a estação é estável.
  # - `de`, `para` e `passo_da_ponte` (de 1 a 40; 0 fora da ponte) são inteiros; a `mistura` (quanto do `para` já
  #   entrou) e o `progresso` (quanto da estação já andou) são as frações deles. Cada valor do mapa (a cor da folha, a
  #   neve…) anda na sua curva sobre a ponte (a E2).
  module Estacao
    module_function

    PONTE_ANTES = 30
    PONTE_DEPOIS = 10
    DIAS_DA_PONTE = PONTE_ANTES + PONTE_DEPOIS

    def estado(minuto)
      dia = minuto / Relogio::MINUTOS_NO_DIA
      dia_do_ano = dia % Relogio::DIAS_NO_ANO
      indice, ja_andou = dia_do_ano.divmod(Relogio::DIAS_NA_ESTACAO)
      dia_da_estacao = ja_andou + 1
      de, para, passo = ponte(indice, dia_da_estacao)
      {
        dia_do_ano: dia_do_ano,
        estacao: Relogio::ESTACOES[indice],
        dia_da_estacao: dia_da_estacao,
        progresso: ja_andou / Relogio::DIAS_NA_ESTACAO.to_f,
        de: de,
        para: para,
        passo_da_ponte: passo,
        mistura: passo / DIAS_DA_PONTE.to_f,
      }
    end

    # [de, para, passo]: no fim da estação, a ponte para a próxima; no começo, o fim da ponte que veio da anterior
    def ponte(indice, dia_da_estacao)
      estacoes = Relogio::ESTACOES
      antes_da_ponte = Relogio::DIAS_NA_ESTACAO - PONTE_ANTES
      if dia_da_estacao > antes_da_ponte
        [estacoes[indice], estacoes[(indice + 1) % estacoes.size], dia_da_estacao - antes_da_ponte]
      elsif dia_da_estacao <= PONTE_DEPOIS
        [estacoes[(indice - 1) % estacoes.size], estacoes[indice], PONTE_ANTES + dia_da_estacao]
      else
        [estacoes[indice], estacoes[(indice + 1) % estacoes.size], 0]
      end
    end
  end
end
