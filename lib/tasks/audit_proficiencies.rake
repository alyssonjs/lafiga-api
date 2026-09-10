# frozen_string_literal: true

# Auditoria do catálogo de proficiências — o PORTÃO de cada fase.
#
#   bundle exec rake dnd:audit_proficiencies
#   CATEGORY=language bundle exec rake dnd:audit_proficiencies
#
# Só lê. Varre TODA proficiência já gravada e pergunta ao catálogo se ela
# resolve. Órfã = string que ninguém consegue interpretar — hoje o modo de
# falha é silencioso (a linha some da ficha), e é isto que o torna visível.
#
# ⚠️ Sai com status 1 se houver órfã, para servir de portão em CI.
namespace :dnd do
  desc 'Audita proficiências gravadas contra o catálogo (0 órfãs = fase completa)'
  task audit_proficiencies: :environment do
    so = ENV['CATEGORY'].presence

    # Onde cada tipo está gravado hoje. Ver o levantamento em
    # `.cursor/dnd-rules/proficiencias-levantamento.md`.
    fontes = {
      'language' => lambda { |s|
        diretas = Array((s.race_summary || {})['languages'])
        # ⚠️ `background_proficiencies` é um balde ÚNICO com cinco tipos
        # misturados (perícia, ferramenta, instrumento, idioma, veículo) e sem
        # etiqueta. Aqui só contam as que o catálogo de idioma reconhece — as
        # outras são de tipos que ainda não foram catalogados, não órfãs.
        balde = Array((s.metadata || {})['background_proficiencies'])
        [diretas, balde]
      },
      # ⚠️ Ferramenta e veículo são categorias DIFERENTES no catálogo, mas a
      # ficha guarda as duas no MESMO array (`class_summary.tools`) — o veículo
      # nunca teve casa própria.
      'tool' => lambda { |s|
        diretas = Array((s.class_summary || {})['tools'])
        balde = Array((s.metadata || {})['background_proficiencies'])
        [diretas, balde]
      },
    }

    # Que categorias do catálogo contam como resolução VÁLIDA para cada fonte.
    #
    # ⚠️ Não dá para resolver sem restringir: o apelido é único globalmente, e a
    # primeira versão disto contava "Gnômico" e "Goblin" como ferramentas
    # escondidas no balde do antecedente, porque a busca sem categoria achava a
    # linha de IDIOMA. Um relatório que mistura os tipos é pior que nenhum,
    # justamente num catálogo cuja razão de existir é separar tipos.
    ACEITAS = {
      'language' => %w[language],
      'tool' => %w[tool vehicle],
    }.freeze

    total_erros = 0
    fontes.each do |categoria, extrator|
      next if so && so != categoria

      catalogadas = Proficiency.where(category: ACEITAS.fetch(categoria, [categoria])).count
      if catalogadas.zero?
        puts "\n== #{categoria}: catálogo VAZIO — nada a auditar (rode o seed antes)"
        next
      end

      duras = Hash.new { |h, k| h[k] = [] }   # tem de resolver
      moles = Hash.new(0)                     # do balde misto: só informativo
      Sheet.find_each do |s|
        diretas, balde = extrator.call(s)
        aceitas = ACEITAS.fetch(categoria, [categoria])
        casa = ->(v) { (p = Proficiency.resolve(v)) && aceitas.include?(p.category) }
        diretas.each { |v| duras[v.to_s] << s.id unless casa.call(v) }
        balde.each   { |v| moles[v.to_s] += 1 if casa.call(v) }
      end

      escopo = Proficiency.where(category: ACEITAS.fetch(categoria, [categoria]))
      puts "\n== #{categoria} — #{catalogadas} no catálogo, #{escopo.joins(:proficiency_aliases).count} apelidos"
      if duras.empty?
        puts '   ✓ 0 ORFAS nas fontes diretas'
      else
        total_erros += duras.size
        puts "   ✗ #{duras.size} ORFAS:"
        duras.sort_by { |_, v| -v.size }.each do |valor, fichas|
          puts format('       %-32s %d ficha(s): %s', valor.inspect, fichas.size, fichas.first(6).join(','))
        end
      end
      unless moles.empty?
        puts "   · #{moles.values.sum} ocorrências de #{categoria} escondidas no balde do antecedente:"
        moles.sort_by { |_, v| -v }.first(8).each { |v, n| puts format('       %-32s %d', v.inspect, n) }
      end
    end

    if total_erros.positive?
      puts "\nFALHOU: #{total_erros} valor(es) sem catálogo."
      exit 1
    end
    puts "\n✓ auditoria limpa"
  end
end
