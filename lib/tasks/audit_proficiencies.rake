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
    }

    total_erros = 0
    fontes.each do |categoria, extrator|
      next if so && so != categoria

      catalogadas = Proficiency.of(categoria).count
      if catalogadas.zero?
        puts "\n== #{categoria}: catálogo VAZIO — nada a auditar (rode o seed antes)"
        next
      end

      duras = Hash.new { |h, k| h[k] = [] }   # tem de resolver
      moles = Hash.new(0)                     # do balde misto: só informativo
      Sheet.find_each do |s|
        diretas, balde = extrator.call(s)
        diretas.each do |v|
          duras[v.to_s] << s.id if Proficiency.resolve(v, category: categoria).nil?
        end
        balde.each { |v| moles[v.to_s] += 1 if Proficiency.resolve(v, category: categoria) }
      end

      puts "\n== #{categoria} — #{catalogadas} no catálogo, #{Proficiency.of(categoria).joins(:proficiency_aliases).count} apelidos"
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
