# frozen_string_literal: true

# O RELÓGIO DO MUNDO (09/10; L0.5, plano B1). A regra está em ProcessoRelogio e Mundo::Ronda.
#
#   bin/rails mundo:relogio   # o laço do serviço `relogio` (deploy/docker-compose.prod.yml), até SIGTERM
#   bin/rails mundo:ronda     # uma ronda só: o cron de reserva (deploy/crontab), ou à mão
#   bin/rails "mundo:semear_argoba[GROUP_ID]"   # DEV: o relógio e a campanha de Argoba para um grupo (L1.1)
namespace :mundo do
  desc 'O processo relogio: avança os mundos a cada 15 s (a pista rápida a cada 5 s), até SIGTERM/SIGINT.'
  task relogio: :environment do
    $stdout.sync = true
    processo = ProcessoRelogio.new
    %w[TERM INT].each { |sinal| Signal.trap(sinal) { processo.parar! } }
    puts "[relogio] no ar (pid #{Process.pid})"
    processo.rodar
    puts '[relogio] parado'
  end

  desc 'Uma ronda do relógio do mundo: o cron de reserva do processo relogio.'
  task ronda: :environment do
    $stdout.sync = true
    ProcessoRelogio.new.ronda
  end

  # O SEED DE DEV de Argoba (L1.1 e L1.2): o relógio do grupo, se ainda não tem (ao meio-dia, como o
  # `POST /dev/mundos`), a campanha de Argoba (`Campanhas::Inicia`) e a casca do mapa do assentamento
  # (`MapaBlocos::Casca`, sem blocos: o protótipo os envia). Rodar de novo não duplica nem desfaz. Também aponta a fauna
  # da ficha que não está no banco de monstros.
  desc 'DEV: dá ao grupo o relógio, a campanha de Argoba e o mapa do assentamento. Uso: bin/rails "mundo:semear_argoba[GROUP_ID]"'
  task :semear_argoba, [:group_id] => :environment do |_tarefa, args|
    abort '[argoba] seed de desenvolvimento: em produção, a campanha nasce com a vila (L1.7)' if Rails.env.production?

    group = Group.find(args[:group_id])
    raise ArgumentError, "o grupo #{group.id} não tem Mestre (dm_user): o mapa precisa de dono" unless group.dm_user

    mundo = group.mundo || group.create_mundo!(epoca_em: Time.current, minuto_na_epoca: 12 * 60, fator: 40)
    campanha = Campanhas::Inicia.call(mundo, regiao: 'argoba')
    puts "[argoba] grupo #{group.id} · mundo #{mundo.id} · campanha #{campanha.id} (#{campanha.nome}) · " \
         "#{campanha.setores.count} setores"
    mapa = MapaBlocos::Casca.call(campanha.setores.find_by!(chave: 'assentamento'), group: group)
    puts "[argoba] mapa do assentamento: battle_map #{mapa.id} (#{mapa.width}×#{mapa.height}, " \
         "#{mapa.mapa_blocos.count} blocos)"

    fauna = campanha.regiao.ficha['biomas'].values.flat_map { |bioma| bioma['fauna'] }.uniq
    faltam = fauna - Monster.where(slug: fauna).pluck(:slug)
    if faltam.empty?
      puts "[argoba] fauna: #{fauna.size} criaturas, todas no banco"
    else
      puts "[argoba] ⚠️ fauna sem ficha no banco: #{faltam.join(', ')}"
    end
  end
end
