# Semeia as ferramentas, instrumentos e kits do PHB (Cap. 5, tabela FERRAMENTAS)
# que ainda nao existem como `Item`.
#
# Motivo: o catalogo tinha 4 das 38 — os 20 `kind: tool` gravados eram quase
# todos homebrew do mestre. Sem as bases, o nome escolhido na criacao de
# personagem nao tem objeto correspondente em lugar nenhum.
#
#   bundle exec rake dnd:seed_phb_tools            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_phb_tools  # so relata
#
# Idempotente: casa por `api_index`, nunca duplica, nunca sobrescreve item
# existente (o homebrew do mestre fica intacto).
namespace :dnd do
  # [nome, api_index, category, custo em PO, peso em kg]
  #
  # `category` espelha `ToolCategory` do front (`toolsCatalog.ts`).
  # `instrument` e a unica com efeito estrutural: poe o item na aba Instrumentos
  # (o balde do EquipmentController filtra por ela).
  PHB_TOOLS = [
    # --- Instrumentos musicais (PHB pg. 154) ---
    ['Alaúde',                        'alaude',                        'instrument', 35,  1.0],
    ['Charamela',                     'charamela',                     'instrument',  2,  0.5],
    ['Cítara',                        'citara',                        'instrument', 30,  1.5],
    ['Cornamusa',                     'cornamusa',                     'instrument', 30,  3.0],
    ['Flauta',                        'flauta',                        'instrument',  2,  0.5],
    ['Flauta de Pã',                  'flauta-de-pa',                  'instrument', 12,  1.0],
    ['Gaita de foles',                'gaita-de-foles',                'instrument', 30,  3.0],
    ['Lira',                          'lira',                          'instrument', 30,  1.0],
    ['Tambor',                        'tambor',                        'instrument',  6,  1.5],
    ['Viola',                         'viola',                         'instrument', 30,  0.5],
    # Fora do PHB, mas EM USO nas fichas (Violino 9x, Trompa 4x). Precisam estar
    # aqui para o reparo de `kind`/`category` alcanca-los: o violino ficou como
    # `kind: armor` e o instrumento aparecia equipavel como armadura na bolsa.
    ['Saltério',                      'salterio',                      'instrument', 30,  1.5],
    ['Trompa',                        'trompa',                        'instrument',  3,  1.0],
    ['Violino',                       'violino',                       'instrument', 30,  0.5],
    # --- Ferramentas de artesao ---
    ['Ferramentas de ferreiro',       'ferramentas-de-ferreiro',       'artisan',    20,  4.0],
    ['Suprimentos de cervejeiro',     'suprimentos-de-cervejeiro',     'artisan',    20,  4.5],
    ['Ferramentas de calígrafo',      'ferramentas-de-caligrafo',      'artisan',    10,  2.5],
    ['Ferramentas de carpinteiro',    'ferramentas-de-carpinteiro',    'artisan',     8,  3.0],
    ['Ferramentas de cartógrafo',     'ferramentas-de-cartografo',     'artisan',    15,  3.0],
    ['Ferramentas de sapateiro',      'ferramentas-de-sapateiro',      'artisan',     5,  2.5],
    ['Ferramentas de funileiro',      'ferramentas-de-funileiro',      'artisan',    50,  5.0],
    ['Ferramentas de joalheiro',      'ferramentas-de-joalheiro',      'artisan',    25,  1.0],
    ['Ferramentas de pedreiro',       'ferramentas-de-pedreiro',       'artisan',    10,  4.0],
    ['Ferramentas de oleiro',         'ferramentas-de-oleiro',         'artisan',    10,  1.5],
    ['Suprimentos de pintor',         'suprimentos-de-pintor',         'artisan',    10,  2.5],
    ['Ferramentas de curtidor',       'ferramentas-de-curtidor',       'artisan',     5,  2.5],
    ['Ferramentas de entalhador',     'ferramentas-de-entalhador',     'artisan',     1,  2.5],
    ['Ferramentas de vidreiro',       'ferramentas-de-vidreiro',       'artisan',    30,  2.5],
    ['Kit de costura',                'kit-de-costura',                'artisan',     1,  2.5],
    ['Utensílios de cozinheiro',      'utensilios-de-cozinheiro',      'artisan',     1,  4.0],
    ['Suprimentos de alquimista',     'suprimentos-de-alquimista',     'artisan',    50,  4.0],
    # --- Conjuntos de jogo ---
    ['Conjunto de dados',             'conjunto-de-dados',             'gaming',      0.1, 0.0],
    ['Xadrez de dragão',              'xadrez-de-dragao',              'gaming',      1,   0.25],
    ['Baralho de cartas',             'baralho-de-cartas',             'gaming',      0.5, 0.0],
    ['Conjunto de Três-Dragões Ante', 'conjunto-de-tres-dragoes-ante', 'gaming',      1,   0.0],
    # --- Kits diversos ---
    ['Kit de disfarce',               'kit-de-disfarce',               'kit',        25,  1.5],
    ['Kit de falsificação',           'kit-de-falsificacao',           'kit',        15,  2.5],
    ['Kit de herbalismo',             'kit-de-herbalismo',             'kit',         5,  1.5],
    ['Kit de envenenador',            'kit-de-envenenador',            'kit',        50,  1.0],
    # --- Outras ---
    ['Ferramentas de ladrão',         'ferramentas-de-ladrao',         'other',      25,  0.5],
    ['Ferramentas de navegação',      'ferramentas-de-navegacao',      'other',      25,  1.0],
    ['Veículos (terrestres)',         'veiculos-terrestres',           'other',       0,  0.0],
    ['Veículos (aquáticos)',          'veiculos-aquaticos',            'other',       0,  0.0],
  ].freeze

  desc 'Semeia as ferramentas/instrumentos/kits do PHB que faltam no catalogo (DRY_RUN=1 so relata)'
  task seed_phb_tools: :environment do
    dry = ENV['DRY_RUN'].present?
    criados = []
    pulados = []
    corrigidos = []

    PHB_TOOLS.each do |name, api_index, category, cost_gp, weight_kg|
      if (existente = Item.find_by(api_index: api_index))
        # Item ja catalogado: NAO sobrescrever nome/custo/peso — pode ser
        # homebrew ajustado pelo mestre. Corrigir so o que e estrutural:
        #   - `kind` errado (ex.: 'Alaude' gravado como `armor`);
        #   - `category` de instrumento, que e o que poe o item na aba propria.
        # Categoria de ferramenta comum ('thieves-tools', 'cook-utensils') fica
        # como esta: nao muda comportamento nenhum.
        fix = {}
        fix[:kind] = 'tool' if existente.kind.to_s != 'tool'
        if category == 'instrument' && existente.category.to_s != 'instrument'
          fix[:category] = 'instrument'
        end

        if fix.any?
          corrigidos << "#{api_index} (#{fix.map { |k, v| "#{k}: #{existente.public_send(k).inspect} -> #{v.inspect}" }.join(', ')})"
          existente.update!(fix) unless dry
        else
          pulados << api_index
        end
        next
      end

      criados << api_index
      next if dry

      Item.create!(
        api_index: api_index,
        name: name,
        kind: 'tool',
        category: category,
        weight_kg: weight_kg,
        # `EquipmentRules.item_cost_cp` le `props['cost_cp']` (padrao do catalogo).
        props: { 'cost_cp' => (cost_gp.to_f * 100).round },
        source: 'PHB',
      )
    end

    puts "[dnd:seed_phb_tools]#{' DRY RUN —' if dry} #{criados.size} a criar, #{corrigidos.size} a corrigir, #{pulados.size} ja OK"
    puts "  criados: #{criados.join(', ')}" if criados.any?
    corrigidos.each { |c| puts "  corrigido: #{c}" }
  end

  # Duplicatas herdadas do catalogo homebrew. TODAS estao em bolsas de jogador
  # (`sheet_items`), entao apagar sem repontar deixaria a bolsa com item orfao.
  # Por isso: repontar PRIMEIRO, apagar depois, e DRY_RUN e o padrao.
  #
  #   bundle exec rake dnd:dedupe_tools            # so relata (padrao)
  #   APPLY=1 bundle exec rake dnd:dedupe_tools    # reponta e apaga
  DUPLICATE_TOOLS = {
    # duplicata => sobrevivente
    'kit-herbalismo' => 'kit-de-herbalismo',
    'kit-desfarse'   => 'kit-de-disfarce',
  }.freeze

  desc 'Reponta e remove ferramentas duplicadas (DRY RUN por padrao; APPLY=1 aplica)'
  task dedupe_tools: :environment do
    apply = ENV['APPLY'].present?

    DUPLICATE_TOOLS.each do |dup_index, keep_index|
      dup  = Item.find_by(api_index: dup_index)
      keep = Item.find_by(api_index: keep_index)

      next puts "  [skip] #{dup_index}: nao existe" if dup.nil?
      next puts "  [skip] #{dup_index}: sobrevivente #{keep_index} nao existe (rode dnd:seed_phb_tools antes)" if keep.nil?

      afetados = SheetItem.where(item_id: dup.id)
      puts "  #{dup_index} -> #{keep_index}: #{afetados.count} sheet_items a repontar"
      next unless apply

      afetados.update_all(item_id: keep.id, item_index: keep.api_index, item_name: keep.name)
      dup.destroy!
      puts "    aplicado."
    end

    puts '[dnd:dedupe_tools] DRY RUN — nada mudou. Use APPLY=1 para aplicar.' unless apply
  end
end
