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
      # ⚠️ Ferramenta lê o que a ficha EMITE, não a coluna crua.
      #
      # A primeira versão media `class_summary.tools` e anunciava "0 órfãs" —
      # medindo 12 de 40 valores. O que chega à ficha é a FUSÃO de classe,
      # antecedente, raça, subclasse e talento, e é lá que estavam os 10
      # órfãos de verdade. Medir meia trilha dá resposta convincente e errada;
      # já custou isto duas vezes neste projeto.
      'tool' => lambda do |s|
        begin
          cmd = CharacterSheetSummaryService.call(sheet_id: s.id)
          payload = cmd.respond_to?(:result) ? cmd.result : cmd
          emitidas = Array(payload.dig(:proficiencies, :tools) || payload.dig('proficiencies', 'tools'))
        rescue StandardError
          emitidas = []
        end
        [emitidas, Array((s.metadata || {})['background_proficiencies'])]
      end,
      'skill' => lambda { |s|
        [Array((s.class_summary || {})['skills']),
         Array((s.metadata || {})['background_proficiencies'])]
      },
      'saving_throw' => ->(s) { [Array((s.class_summary || {})['saving_throws']), []] },
      'armor' => ->(s) { [Array((s.class_summary || {})['armor_proficiencies']), []] },
      'weapon' => ->(s) { [Array((s.class_summary || {})['weapon_proficiencies']), []] },
    }

    # ⚠️ LIXO CONHECIDO — não é proficiência e não vai virar linha do catálogo.
    #
    # Catalogá-lo seria mentir; deixá-lo como órfã deixaria o portão vermelho
    # para sempre e o portão perderia o sentido. Fica listado, com o motivo, e
    # contado à parte. Sair daqui é limpeza de DADO, que é outra fase.
    # ⚠️ `background_rules.rb:326` monta `'Jogo de ' + label` e a fila de
    # escolhas (`tool_queue.shift`) entrega valor do slot ERRADO — daí
    # "Jogo de Veículos Terrestres" e o duplamente quebrado "Jogo de Jogo de
    # Escolher". É bug PRÉ-EXISTENTE, e o catálogo é que o tornou visível.
    # Catalogá-los seria catalogar um defeito.
    # ⚠️ Só os TRÊS em que o miolo NÃO é conjunto de jogo — a fila entregou o
    # slot errado e não dá para saber o que o jogador escolheu. Os outros cinco
    # ("Jogo de Dados", "Jogo de Cartas"…) SÃO recuperáveis e viraram apelido no
    # seed: o jogador tem mesmo aquela proficiência, só prefixada, e
    # quarentená-los tiraria dele o que o antecedente concedeu.
    LIXO_JOGO_DE = [
      'Jogo de Ferramentas de Ladrão',
      'Jogo de Veículos Terrestres',
      'Jogo de Jogo de Escolher',
    ].freeze

    LIXO = {
      'armas' => 'fragmento de "armas simples": 3 fichas de Bruxo têm ' \
                 '["armas", "simple"] e o Bruxo só tem armas simples — ' \
                 'o valor é redundante, e adivinhar o que ele queria dizer ' \
                 'daria proficiência errada a um Guerreiro com o mesmo defeito',
      # Placeholders de escolha PENDENTE, não proficiências.
      'Instrumento musical (escolher)' => 'placeholder de escolha ainda não feita',
    }.merge(
      LIXO_JOGO_DE.index_with do |v|
        "prefixo 'Jogo de ' + valor do slot errado (background_rules.rb:326, " \
        "bug pré-existente): #{v.sub('Jogo de ', '').inspect} não é conjunto de jogo"
      end,
    ).freeze

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
      'skill' => %w[skill],
      'saving_throw' => %w[saving_throw],
      'armor' => %w[armor],
      # A ficha mistura categoria de arma ("simple") e arma ("longsword") no
      # MESMO array — nunca houve separação.
      'weapon' => %w[weapon weapon_category],
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
      lixo_visto = Hash.new(0)                # conhecido, aguardando limpeza
      Sheet.find_each do |s|
        diretas, balde = extrator.call(s)
        aceitas = ACEITAS.fetch(categoria, [categoria])
        casa = ->(v) { (p = Proficiency.resolve(v)) && aceitas.include?(p.category) }
        diretas.each do |v|
          next if LIXO.key?(v.to_s)

          duras[v.to_s] << s.id unless casa.call(v)
        end
        diretas.each { |v| lixo_visto[v.to_s] += 1 if LIXO.key?(v.to_s) }
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
      unless lixo_visto.empty?
        puts "   ! lixo conhecido (não é proficiência, aguarda limpeza de dado):"
        lixo_visto.sort_by { |_, v| -v }.each do |v, n|
          puts format('       %-22s %d ocorrência(s) — %s', v.inspect, n, LIXO[v])
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
