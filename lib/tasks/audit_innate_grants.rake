# frozen_string_literal: true

# FASE 3 das magias — a PROSA do traço bate com o DADO estruturado?
#
#   bundle exec rake dnd:audit_innate_grants
#
# Cada `trait_definition` tem duas descrições da mesma regra: o texto que o
# mestre escreve (`description`, que é o que a mesa lê na ficha) e o
# `grants.spells`, que é o que o código concede. Nada os mantinha em acordo.
#
# ⚠️ Achado que motivou este rake: o `abyssal_legacy` promete "5º: Cativar" na
# prosa e concede `charm-person` no dado. "Cativar" é `enthrall` (nível 2) e
# "Enfeitiçar Pessoa" é `charm-person` (nível 1) — magias DIFERENTES. A ficha
# mostra uma coisa e o texto promete outra, e ninguém repara porque as duas
# leituras nunca se encontram.
#
# NÃO derruba: divergência aqui é decisão do mestre (qual das duas está certa),
# não defeito de código.
namespace :dnd do
  desc 'FASE 3 — confere a prosa dos traços raciais contra os grants estruturados'
  task audit_innate_grants: :environment do
    defs = RaceRules.trait_definitions || {}
    resolvedor = SpellResolver.new

    com_magia = defs.select do |_k, v|
      g = v[:grants] || v['grants']
      g.is_a?(Hash) && (g[:spells] || g['spells']).present?
    end

    # ── quem referencia cada traço, para nomear o culpado ──
    yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))
    donos = Hash.new { |h, k| h[k] = [] }
    anda = lambda do |no, tipo, chave|
      next unless no.is_a?(Hash)

      Array(no['traits']).each do |t|
        donos[(t['key'] || t[:key]).to_s] << (no['name'] || chave) if t.is_a?(Hash)
      end
      (no['subraces'] || {}).each { |k, sr| anda.call(sr, 'SubRace', k) } if no['subraces'].is_a?(Hash)
    end
    yaml.each { |k, r| anda.call(r, 'Race', k) } if yaml.is_a?(Hash)

    divergencias = []
    linhas = []

    com_magia.each do |chave, defi|
      prosa = (defi[:description] || defi['description']).to_s
      g = defi[:grants] || defi['grants']
      entradas = Array(g[:spells] || g['spells'])

      # ── o que o DADO concede ── (medido primeiro: a prosa é lida CONTRA ele)
      concedidas = entradas.map do |e|
        slug = (e[:spell] || e['spell']).to_s
        m = resolvedor.resolve(slug)
        {
          slug: slug, magia: m, nivel: (e[:minimum_level] || e['minimum_level'] || 1).to_i,
          uso: (e[:usage] || e['usage']).to_s
        }
      end

      quem = donos[chave.to_s].uniq
      linhas << { chave: chave.to_s, quem: quem, concedidas: concedidas }

      # ── o que a PROSA promete ──
      #
      # ⚠️ A primeira versão usava UMA expressão sobre a frase inteira e produziu
      # SETE falsos positivos: o parêntese final ("(CAR)", "(CD/ataque usam
      # CAR)") fazia o lookahead falhar e matava a última entrada de cada prosa.
      # Pior — escondeu o achado real: reportou "Enfeitiçar Pessoa não
      # prometida" em vez de "a prosa promete Cativar, que é outra magia".
      #
      # Agora parte por `;` e lê segmento a segmento, que é como o texto é
      # escrito. Segmento SEM marcador de nível só conta como promessa se
      # nomear uma magia — senão "CAR é seu atributo de conjuração para esse
      # truque" viraria uma promessa fantasma.
      promessas = []
      prosa.split(';').each do |bruto|
        seg = bruto.gsub(/\([^)]*\)/, ' ').sub(/\.\s*\z/, '').strip
        next if seg.empty?

        limite = seg[/1\s*\/\s*L\s*(Desc|Curto)/i]
        corpo = seg.gsub(/1\s*\/\s*L\s*(Desc|Curto)/i, ' ').squeeze(' ').strip

        if (m = corpo.match(/\A(\d+)\s*º\s*:\s*(.+)\z/))
          # Com marcador de nível é SEMPRE promessa — mesmo que o nome não
          # resolva, porque é aí que mora o erro de digitação que importa.
          promessas << { nivel: m[1].to_i, nome: m[2].strip, limite: limite, marcado: true }
          next
        end

        # Sem marcador: só conta se nomear uma magia que o dado concede.
        achada = concedidas.find { |c| c[:magia] && corpo.match?(/#{Regexp.escape(ActiveSupport::Inflector.transliterate(c[:magia].name))}/i) ||
                                       (c[:magia] && ActiveSupport::Inflector.transliterate(corpo).match?(/#{Regexp.escape(ActiveSupport::Inflector.transliterate(c[:magia].name))}/i)) }
        promessas << { nivel: achada[:nivel], nome: achada[:magia].name, limite: limite, marcado: false } if achada
      end

      # ── confronto ──
      # A prosa é a intenção; o dado é o que acontece. Casar por MAGIA RESOLVIDA
      # (não por texto) é o que apanha "Cativar" ≠ "Enfeitiçar Pessoa": os dois
      # são nomes válidos, de magias diferentes.
      promessas.each do |p|
        alvo = resolvedor.resolve(p[:nome])
        if alvo.nil?
          divergencias << {
            traco: chave.to_s, quem: quem, tipo: 'nome_sem_catalogo', nivel: p[:nivel],
            texto: "a prosa promete #{p[:nome].inspect} e o catálogo não tem magia com esse nome"
          }
          next
        end

        par = concedidas.find { |c| c[:magia]&.id == alvo.id }
        if par.nil?
          concedida_no_nivel = concedidas.find { |c| c[:nivel] == p[:nivel] }
          divergencias << {
            traco: chave.to_s, quem: quem, tipo: 'magia_diferente', nivel: p[:nivel],
            texto: "no #{p[:nivel]}º a prosa promete #{alvo.name.inspect} (#{alvo.api_index}, nv#{alvo.level}) " \
                   "mas o dado concede #{concedida_no_nivel ? "#{concedida_no_nivel[:magia]&.name.inspect} (#{concedida_no_nivel[:slug]})" : 'nada'}"
          }
          next
        end

        if par[:nivel] != p[:nivel]
          divergencias << {
            traco: chave.to_s, quem: quem, tipo: 'nivel_diferente',
            texto: "#{alvo.name}: a prosa diz #{p[:nivel]}º, o dado diz #{par[:nivel]}º"
          }
        end

        prosa_limitada = p[:limite].present?
        dado_limitado = par[:uso].match?(/rest|desc/i)
        if prosa_limitada != dado_limitado
          divergencias << {
            traco: chave.to_s, quem: quem, tipo: 'limite_diferente',
            texto: "#{alvo.name}: a prosa #{prosa_limitada ? 'limita' : 'NÃO limita'} e o dado #{dado_limitado ? "limita (#{par[:uso]})" : "NÃO limita (#{par[:uso]})"}"
          }
        end
      end

      # O inverso: o dado concede algo que a prosa não menciona.
      #
      # ⚠️ Só quando é achado NOVO. Quando a prosa já foi apanhada a prometer
      # outra magia naquele nível, dizer também "esta não é mencionada" é o eco
      # do mesmo defeito — e um relatório que conta duas vezes faz o mestre
      # procurar dois problemas onde há um.
      niveis_ja_apontados = divergencias.select { |d| d[:traco] == chave.to_s }
                                        .map { |d| d[:nivel] }.compact
      concedidas.each do |c|
        next if c[:magia].nil?
        next if promessas.any? { |p| resolvedor.resolve(p[:nome])&.id == c[:magia].id }
        next if niveis_ja_apontados.include?(c[:nivel])

        divergencias << {
          traco: chave.to_s, quem: quem, tipo: 'nao_prometida', nivel: c[:nivel],
          texto: "o dado concede #{c[:magia].name.inspect} (#{c[:nivel]}º) e a prosa não a menciona"
        }
      end
    end

    puts "== o que cada traço concede HOJE (o dado é quem manda)\n\n"
    linhas.sort_by { |l| l[:quem].first.to_s }.each do |l|
      onde = l[:quem].empty? ? '⚠️ ninguém referencia' : l[:quem].join(', ')
      puts "  #{l[:chave]}  (#{onde})"
      l[:concedidas].each do |c|
        limite = c[:uso].match?(/rest|desc/i) ? '1/descanso longo' : 'à vontade'
        nome = c[:magia] ? c[:magia].name : "⚠️ #{c[:slug]} NÃO RESOLVE"
        puts format('      nv%-3s %-26s %s', c[:nivel], nome, limite)
      end
      puts
    end

    puts "== divergências entre a PROSA e o DADO: #{divergencias.size}\n\n"
    if divergencias.empty?
      puts '  ✓ nenhuma — o texto que a mesa lê descreve o que o código faz'
    else
      divergencias.group_by { |d| d[:tipo] }.each do |tipo, ds|
        puts "  [#{tipo}]"
        ds.each do |d|
          onde = d[:quem].empty? ? d[:traco] : "#{d[:quem].join(', ')} (#{d[:traco]})"
          puts "     ⚠️ #{onde}: #{d[:texto]}"
        end
        puts
      end
      puts '  Decisão é do mestre: corrigir a prosa ou o dado. NÃO derruba o portão.'
    end
  end
end
