# frozen_string_literal: true

class Mundo
  # Os EVENTOS SISTÊMICOS (09/10; L0.7, plano I7, GDD §116). O catálogo (`config/mundo/eventos.yml`) diz a base, o piso,
  # o teto e o peso de cada fator; o estado do mundo diz quais fatores valem agora, e quantas vezes. As decisões do grupo
  # mexem na chance: o poço, o curandeiro e o hospital baixam o risco de doença.
  #
  # `ativos`: as chaves dos fatores que valem (`%w[pantano poco]`), ou chave → vezes (`{ 'populacao_alta' => 2 }`).
  module Eventos
    module_function

    ARQUIVO = 'config/mundo/eventos.yml'

    def catalogo
      @catalogo ||= carrega(Rails.root.join(ARQUIVO))
    end

    # A chance que o estado do mundo dá ao evento, com cada fator:
    # → { 'evento', 'nome', 'base', 'piso', 'teto', 'fatores' => [{ 'chave', 'nome', 'valor', 'vezes', 'soma' }], 'chance' }
    def chance(evento, ativos:)
      e = evento!(evento)
      fatores = vezes_de(ativos).map do |chave, vezes|
        f = e['fatores'][chave] or raise ArgumentError, "fator desconhecido em #{evento}: #{chave}"
        { 'chave' => chave, 'nome' => f['nome'], 'valor' => f['valor'], 'vezes' => vezes, 'soma' => f['valor'] * vezes }
      end
      chance = (e['base'] + fatores.sum { |f| f['soma'] }).clamp(e['piso'], e['teto'])
      e.slice('nome', 'base', 'piso', 'teto').merge('evento' => evento.to_s, 'fatores' => fatores, 'chance' => chance)
    end

    # Rola o evento no d100 (fonte hmac: a `chave` decide o dado, e repetir a chave devolve a mesma rolagem).
    # → { 'evento', 'acontece', 'chance', 'rolado', 'rolagem' }
    def rola(evento, ativos:, chave:, contexto: {})
      c = chance(evento, ativos: ativos)
      rolagem = Dados::Estrategico.call(
        chave: chave, base: c['base'], fatores: c['fatores'], piso: c['piso'], teto: c['teto'], fonte: :hmac,
        contexto: contexto.merge('evento' => c['evento']),
      )
      {
        'evento' => c['evento'], 'acontece' => rolagem.detalhe['acontece'], 'chance' => rolagem.detalhe['chance'],
        'rolado' => rolagem.detalhe['rolado'], 'rolagem' => rolagem.id,
      }
    end

    def evento!(evento)
      catalogo[evento.to_s] or raise ArgumentError, "evento sistêmico desconhecido: #{evento.inspect}"
    end

    def vezes_de(ativos)
      lista = ativos.is_a?(Hash) ? ativos.to_h.transform_keys(&:to_s) : Array(ativos).map { |a| [a.to_s, 1] }.to_h
      lista.each { |chave, vezes| raise ArgumentError, "vezes inválido em #{chave}: #{vezes.inspect}" unless vezes.is_a?(Integer) && vezes >= 0 }
      lista.sort.to_h
    end

    # o catálogo carregado e conferido: só inteiros (D11), piso e teto em 0..100
    def carrega(caminho)
      eventos = YAML.safe_load(File.read(caminho))
      eventos.each do |nome, e|
        numeros = [e['base'], e['piso'], e['teto'], *e['fatores'].values.map { |f| f['valor'] }]
        raise ArgumentError, "#{nome}: só inteiros no catálogo de eventos" unless numeros.all?(Integer)
        raise ArgumentError, "#{nome}: piso e teto fora de 0..100" unless e['piso'].between?(0, 100) && e['teto'].between?(e['piso'], 100)
      end
      eventos.freeze
    end
  end
end
