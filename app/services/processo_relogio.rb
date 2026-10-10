# frozen_string_literal: true

require 'set'

# O PROCESSO `relogio` (09/10; L0.5, plano B1): o laço que faz as vilas andarem sozinhas, com ou sem gente online.
# Roda no serviço `relogio` do `deploy/docker-compose.prod.yml` (`bin/rails mundo:relogio`).
#
# - A cada 5 s (`TIQUE`), a pista rápida: o combate automático entra aqui no L4.6. Por ora, nada.
# - A cada 15 s (`TIQUES_POR_RONDA`), uma ronda dos mundos (`Mundo::Ronda`): 10 minutos de jogo no fator 40.
# - Para no SIGTERM/SIGINT (o `docker stop`), ao fim do tique em curso.
# - Uma ronda que falha não derruba o laço. O evento que segura um mundo é avisado uma vez por processo.
#
# Fica fora de `app/services/mundo` de propósito: aqui se lê o relógio da máquina (o agora de cada ronda), coisa que o
# mundo não faz (plano D11).
class ProcessoRelogio
  TIQUE = 5
  TIQUES_POR_RONDA = 3

  def initialize(saida: $stdout, dorme: ->(segundos) { sleep(segundos) }, agora: -> { Time.current })
    @saida = saida
    @dorme = dorme
    @agora = agora
    @parar = false
    @avisados = Set.new
  end

  def parar!
    @parar = true
  end

  # Roda até `parar!`; `max_tiques` só nos testes.
  def rodar(max_tiques: nil)
    tique = 0
    loop do
      pista_rapida
      ronda if (tique % TIQUES_POR_RONDA).zero?
      tique += 1
      break if @parar || (max_tiques && tique >= max_tiques)

      @dorme.call(TIQUE)
      break if @parar
    end
  end

  def ronda
    resultado = Rails.application.reloader.wrap do
      ActiveRecord::Base.connection.verify!
      Mundo::Ronda.call(agora: @agora.call)
    end
    relata(resultado)
    resultado
  rescue StandardError => e
    @saida.puts "[relogio] a ronda falhou: #{e.class}: #{e.message}"
    nil
  end

  # L4.6: os turnos da IA no combate automático
  def pista_rapida; end

  private

  def relata(r)
    return @saida.puts('[relogio] outra ronda em curso; esta pulou') unless r.rodou

    if r.processados.positive? || r.ocupados.positive?
      ocupados = r.ocupados.positive? ? ", #{r.ocupados} ocupado(s)" : ''
      @saida.puts "[relogio] #{r.mundos} mundo(s), #{r.processados} evento(s)#{ocupados}"
    end
    r.erros.each { |mundo_id, erro| @saida.puts "[relogio] o mundo #{mundo_id} parou num evento: #{erro}" }
    r.parados.reject { |p| @avisados.include?(p[1]) }.each do |mundo_id, evento_id, tipo, tentativas, erro|
      @saida.puts "[relogio] ⚠️ o evento #{evento_id} (#{tipo}) segura o mundo #{mundo_id}: #{tentativas} falhas. #{erro}"
    end
    @avisados = r.parados.map { |p| p[1] }.to_set
  end
end
