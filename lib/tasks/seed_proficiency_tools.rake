# frozen_string_literal: true

# FASE 0 do catálogo de proficiências — FERRAMENTAS e VEÍCULOS.
#
#   bundle exec rake dnd:seed_proficiency_tools            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_proficiency_tools  # só relata
#
# Idempotente: casa por `api_index` e nunca apaga nada.
#
# ⚠️ Este é o tipo com o pior histórico do projeto: foi aqui que "Veículos
# terrestres" acabou com QUATRO grafias e 14 proficiências ficaram órfãs em
# silêncio. As fontes conferidas, e o que cada uma trouxe de diferente:
#
#   1. `front-lafiga/src/app/data/toolsCatalog.ts` — o catálogo curado (42) e o
#      mapa `TOOL_ALIASES`, que já resolvia parte da bagunça;
#   2. `api/app/services/background_rules.rb` — 48 valores, com "Kit de
#      Disfarce" E "Kit de disfarce" na MESMA lista, além de "Coureiro",
#      "Vidraceiro", "Marceneiro" e "Tecelão", que são outras palavras para
#      ofícios que o front já nomeava de outro jeito;
#   3. `api/config/race_rules.yml` — trouxe "Voz (instrumento)";
#   4. `Item` (kind: tool, 55 linhas) — o catálogo que o jogador compra.
#
# ⚠️ O CANÔNICO é o nome EM USO, não o do livro. O livro pt-BR (pg. 154) grafa
# "Ferramentas de coureiro", "Suprimentos de caligrafia", "Ferramentas de
# pintor" e "Ferramentas de costureiro" — mas o catálogo de `Item`, que é o que
# o jogador vê e compra, já usa os nomes do front. Adotar o livro aqui criaria
# uma divergência NOVA entre proficiência e item, que é exatamente o defeito
# que este catálogo existe para acabar. O nome do livro entra como APELIDO, e a
# divergência fica registrada como decisão de produto.
namespace :dnd do
  # nome canônico, sub-categoria, [apelidos], fonte
  FERRAMENTAS = [
    # ── Ferramentas de artesão (17 do livro, com os nomes em uso) ──────────
    ['Ferramentas de ferreiro',     'artisan'],
    ['Suprimentos de cervejeiro',   'artisan', ['Ferramentas de Cervejeiro']],
    ['Ferramentas de calígrafo',    'artisan', ['Suprimentos de caligrafia', 'Suprimentos de calígrafo', 'Ferramentas de Calígrafo']],
    ['Ferramentas de carpinteiro',  'artisan', ['Ferramentas de Marceneiro']],
    ['Ferramentas de cartógrafo',   'artisan'],
    ['Ferramentas de sapateiro',    'artisan'],
    ['Ferramentas de funileiro',    'artisan'],
    ['Ferramentas de joalheiro',    'artisan'],
    ['Ferramentas de pedreiro',     'artisan'],
    ['Ferramentas de oleiro',       'artisan'],
    ['Suprimentos de pintor',       'artisan', ['Ferramentas de pintor']],
    ['Ferramentas de curtidor',     'artisan', ['Ferramentas de coureiro', 'Ferramentas de couro', 'Kit de Coureiro']],
    ['Ferramentas de entalhador',   'artisan', ['Ferramentas de escultor']],
    ['Ferramentas de vidreiro',     'artisan', ['Ferramentas de Vidraceiro']],
    # "Tecelão" é o mesmo ofício: o livro pt-BR grafa "Ferramentas de
    # costureiro" onde o inglês tem weaver's tools.
    ['Kit de costura',              'artisan', ['Ferramentas de costureiro', 'Ferramentas de Tecelão']],
    ['Utensílios de cozinheiro',    'artisan', ['Ferramentas de Cozinha', 'Ferramentas de Artesão (Cozinheiro)']],
    ['Suprimentos de alquimista',   'artisan', ['Ferramentas de Alquimista', 'Kit de Alquimista']],
    # ⚠️ FORA DO LIVRO: o PHB pt-BR só tem "Ferramentas de ferreiro". Ferreiro
    # de armaduras é ofício DIFERENTE, não grafia diferente — por isso linha
    # própria, e não apelido de ferreiro. Chegou por `background_rules.rb`.
    ['Ferramentas de ferreiro de armaduras', 'artisan', [], 'homebrew'],

    # ── Instrumentos musicais ─────────────────────────────────────────────
    # ⚠️ União deliberada: os 10 do livro MAIS os 6 que o front já oferecia
    # (Charamela, Cítara, Cornamusa, Viola, Saltério, Trompa) e que têm escolha
    # gravada em ficha. Cortar qualquer um órfãos essas fichas — foi o que a
    # unificação de ago/2026 já tinha aprendido, quando 14 proficiências
    # ficaram órfãs por alguém ter feito interseção em vez de união.
    ['Alaúde',          'instrument', ['Alaude']],
    ['Flauta',          'instrument'],
    ['Flauta de Pã',    'instrument', ['Flauta de pa']],
    ['Gaita de foles',  'instrument'],
    ['Lira',            'instrument'],
    ['Tambor',          'instrument'],
    ['Violino',         'instrument'],
    ['Oboé',            'instrument'],
    ['Trombeta',        'instrument'],
    ['Xilofone',        'instrument'],
    ['Charamela',       'instrument'],
    ['Cítara',          'instrument'],
    ['Cornamusa',       'instrument'],
    ['Viola',           'instrument'],
    ['Saltério',        'instrument'],
    ['Trompa',          'instrument'],
    ['Harpa',           'instrument'],
    # `race_rules.yml` concede "Voz (instrumento)" a uma raça. Não está no
    # livro; entra marcado em vez de ser descartado.
    ['Voz (instrumento)', 'instrument', ['Voz'], 'homebrew'],

    # ── Conjuntos de jogo ─────────────────────────────────────────────────
    # ⚠️ Os apelidos com prefixo "Jogo de " vêm de `background_rules.rb:326`,
    # que monta `'Jogo de ' + label`. Quando o miolo É um conjunto de jogo, o
    # jogador TEM mesmo essa proficiência — só prefixada. Descartá-los tiraria
    # dele o que o antecedente concedeu. (Quando o miolo NÃO é conjunto de jogo,
    # a fila entregou o slot errado; esses ficam em quarentena na auditoria, não
    # aqui, porque adivinhar o que o jogador escolheu seria inventar.)
    ['Conjunto de dados',              'gaming', ['Dados', 'Jogo de Dados', 'Jogo de Conjunto de dados']],
    ['Baralho de cartas',              'gaming', ['Cartas', 'Jogo de Cartas', 'Jogo de Baralho de cartas']],
    ['Xadrez de dragão',               'gaming', ['Jogo de Xadrez de dragão']],
    ['Conjunto de Três-Dragões Ante',  'gaming', ['Jogo dos três dragões', 'Três-Dragões Ante']],

    # ── Kits ──────────────────────────────────────────────────────────────
    ['Kit de disfarce',      'kit', ['Kit disfarce']],
    ['Kit de falsificação',  'kit', ['Ferramentas de falsificação']],
    ['Kit de herbalismo',    'kit', ['Kit Herbalismo']],
    ['Kit de envenenador',   'kit', ['Kit de veneno', 'Kit de Venenos']],

    # ── Outras ────────────────────────────────────────────────────────────
    ['Ferramentas de ladrão',    'other'],
    ['Ferramentas de navegação', 'other', ['Ferramentas de navegador', 'Utensílios de navegação']],
  ].freeze

  # ⚠️ VEÍCULO É CATEGORIA PRÓPRIA, e são só DUAS proficiências.
  #
  # O `VEHICLE_CATALOG` do front lista 10 nomes (Biga, Carroça, Galera…) como se
  # cada um fosse uma proficiência. Não são: são ITENS, e já vivem como tal
  # (`dnd:seed_phb_vehicles`, `kind: gear` + `category: vehicle_land`). Ninguém
  # é proficiente em "Galera" — é proficiente em "Veículos (aquáticos)".
  # Medido: nenhuma ficha tem veículo concreto como proficiência.
  #
  # As QUATRO grafias que já custaram 14 órfãs entram todas como apelido.
  VEICULOS = [
    ['Veículos (terrestres)', 'land',  ['Veículos terrestres', 'Veículos (terrestre)', 'vehicles_land']],
    ['Veículos (aquáticos)',  'water', ['Veículos aquáticos', 'Veículos (aquático)', 'vehicles_water']],
  ].freeze

  desc 'FASE 0 — semeia o catálogo de FERRAMENTA e VEÍCULO (DRY_RUN=1 relata)'
  task seed_proficiency_tools: :environment do
    seco = ENV['DRY_RUN'].present?
    criados = atualizados = apelidos = 0

    aplicar = lambda do |nome, categoria, sub, extras, fonte, prefixo|
      idx = "#{prefixo}-#{Proficiency.normalize(nome).tr(' ', '-')}"
      p = Proficiency.find_or_initialize_by(api_index: idx)
      novo = p.new_record?
      p.assign_attributes(name: nome, category: categoria, sub_category: sub,
                          metadata: {}, source: fonte || 'PHB', published: true)
      if seco
        puts "  #{novo ? 'CRIARIA' : 'atualizaria'} #{idx.ljust(42)} #{nome} (#{sub}#{fonte ? ", #{fonte}" : ''})"
      else
        p.save!
        ([nome] + Array(extras)).each do |a|
          antes = ProficiencyAlias.count
          p.add_alias!(a)
          apelidos += 1 if ProficiencyAlias.count > antes
        end
      end
      novo ? criados += 1 : atualizados += 1
    end

    ActiveRecord::Base.transaction do
      FERRAMENTAS.each { |nome, sub, extras, fonte| aplicar.call(nome, 'tool', sub, extras, fonte, 'tool') }
      VEICULOS.each    { |nome, sub, extras|        aplicar.call(nome, 'vehicle', sub, extras, nil, 'veh') }
      raise ActiveRecord::Rollback if seco
    end

    puts "\n#{seco ? '[DRY RUN] ' : ''}ferramenta+veículo: #{criados} criados, #{atualizados} já existiam, #{apelidos} apelidos novos"
    unless seco
      puts "ferramentas no catálogo: #{Proficiency.of('tool').count}"
      puts "veículos no catálogo:    #{Proficiency.of('vehicle').count}"
    end
  end
end
