# frozen_string_literal: true

# Importa as ervas de herbalismo e as plantas venenosas (coleta + preparo).
#
#   bin/rails dnd:import_herbs           # importa/atualiza
#   DRY_RUN=1 bin/rails dnd:import_herbs # só relata
#
# Fonte: `db/data/herbs_seed.json` (das Tabelas de Ervas e de Venenos).
# Três passos, nesta ordem:
#   1. remove os 10 placeholders genéricos que seedavam a família `herb`
#      (eram lista-base para a aba não nascer vazia; as reais os substituem);
#   2. importa 234 materiais (`herb` + `poison-herb`), idempotente por api_index;
#   3. ENRIQUECE os venenos de criatura do DMG que JÁ existem como
#      consumable/poison — nunca cria material duplicado para eles.
#
# ⚠️ `create!`/`update!`, nunca `insert_all`: em banco carregado do schema.rb a
# validação do model é a única guarda (o 6.0 não despeja CHECK constraints).
namespace :dnd do
  desc 'Importa ervas de herbalismo e plantas venenosas'
  task import_herbs: :environment do
    dry = ENV['DRY_RUN'].present?
    seed = JSON.parse(File.read(Rails.root.join('db', 'data', 'herbs_seed.json')))
    stats = Hash.new(0)
    sem_acento = ->(txt) { txt.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip }
    puts "== import_herbs #{'(DRY RUN)' if dry} =="

    # ── 1. placeholders fora ──────────────────────────────────────────────────
    PLACEHOLDERS = %w[
      mat-folha-de-athelas mat-raiz-de-mandragora mat-erva-do-sono mat-visco-negro
      mat-flor-de-lotus mat-musgo-cavernoso mat-casca-de-salgueiro
      mat-cogumelo-bulboso mat-cicuta mat-beladona
    ].freeze
    Item.where(api_index: PLACEHOLDERS).find_each do |ph|
      if dry
        stats[:placeholders_a_remover] += 1
        next
      end
      if ph.destroy
        stats[:placeholders_removidos] += 1
      else
        # Em uso numa receita (`restrict_with_error`): fica, com aviso — apagar
        # por baixo de uma receita a deixaria muda.
        stats[:placeholders_mantidos_em_uso] += 1
        warn "  ⚠️ placeholder em uso, mantido: #{ph.name} (#{ph.errors.full_messages.first})"
      end
    end

    # ── 2. materiais ──────────────────────────────────────────────────────────
    seed['materiais'].each do |m|
      props = {
        'unit' => 'un',
        'plant_type' => m['plant_type'],
        'foraging' => m['foraging'],
        'preparation' => m['preparation'],
      }.compact
      props['needs_review'] = 'sem preço ou raridade na planilha' if m['needs_review']

      item = Item.find_by(api_index: m['api_index'])
      if item
        mudou = {}
        mudou[:name]        = m['name']        if item.name.blank?
        mudou[:category]    = m['category']    if item.category != m['category']
        mudou[:rarity]      = m['rarity']      if item.rarity.blank? && m['rarity']
        mudou[:value_gp]    = m['value_gp']    if item.value_gp.blank? && m['value_gp']
        mudou[:description] = m['description'] if item.description.blank? && m['description']
        # Colheita e preparo são DO CATÁLOGO (a planilha manda); o resto do
        # props (edições do mestre) fica intacto.
        novos_props = item.props.to_h.merge(props)
        mudou[:props] = novos_props if novos_props != item.props.to_h
        item.update!(mudou) if mudou.any? && !dry
        stats[mudou.any? ? :materiais_atualizados : :materiais_intactos] += 1
      else
        Item.create!(api_index: m['api_index'], name: m['name'], kind: 'material',
                     category: m['category'], rarity: m['rarity'], value_gp: m['value_gp'],
                     description: m['description'], source: m['source'], props: props) unless dry
        stats[:materiais_criados] += 1
      end
    end

    # ── 3. venenos do DMG: enriquecer, nunca duplicar ─────────────────────────
    indice = Item.where(kind: 'consumable', category: 'poison')
                 .pluck(:id, :name).to_h { |id, n| [sem_acento.call(n), id] }
    seed['venenos_dmg'].each do |v|
      alvo = Item.find_by(id: indice[sem_acento.call(v['catalog_name'])])
      if alvo.nil?
        stats[:venenos_dmg_nao_achados] += 1
        warn "  ⚠️ veneno DMG não achado no catálogo: #{v['catalog_name']} (planilha: #{v['sheet_name']})"
        next
      end
      mudou = {}
      mudou[:value_gp]    = v['value_gp']    if alvo.value_gp.blank? && v['value_gp']
      mudou[:rarity]      = v['rarity']      if alvo.rarity.blank? && v['rarity']
      mudou[:description] = v['description'] if alvo.description.blank? && v['description']
      novos_props = alvo.props.to_h.merge(
        'foraging' => v['foraging'], 'preparation' => v['preparation'],
      )
      mudou[:props] = novos_props if novos_props != alvo.props.to_h
      alvo.update!(mudou) if mudou.any? && !dry
      stats[mudou.any? ? :venenos_dmg_enriquecidos : :venenos_dmg_intactos] += 1
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-28s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
