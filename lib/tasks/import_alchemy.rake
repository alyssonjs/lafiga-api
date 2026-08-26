# frozen_string_literal: true

# Importa matérias-primas, produtos alquímicos e suas receitas.
#
#   bin/rails dnd:import_alchemy          # importa/atualiza
#   DRY_RUN=1 bin/rails dnd:import_alchemy  # só relata, não grava
#
# Fonte: `db/data/alchemy_seed.json` (gerado da planilha de poções + Manual do
# Alquimista) e `db/data/base_materials.yml` (gemas, metais, ervas, culinária).
#
# ⚠️ Usa `create!`/`update!`, NUNCA `insert_all`: o `schema.rb` do Rails 6.0 não
# despeja CHECK constraints, então em bancos criados do schema a validação do
# model é a ÚNICA coisa que impede um ingrediente sem alvo.
#
# Idempotente por `api_index`: rodar duas vezes não duplica nada.
namespace :dnd do
  desc 'Importa matérias-primas, produtos alquímicos e receitas'
  task import_alchemy: :environment do
    dry = ENV['DRY_RUN'].present?
    base = Rails.root.join('db', 'data')
    seed = JSON.parse(File.read(base.join('alchemy_seed.json')))
    bases = YAML.safe_load(File.read(base.join('base_materials.yml')))

    stats = Hash.new(0)
    puts "== import_alchemy #{'(DRY RUN)' if dry} =="

    # Índice por nome NORMALIZADO (sem acento, sem caixa). A extensão `unaccent`
    # não está ligada neste banco, e o catálogo mistura "Agua Benta" com
    # "Água benta (frasco)" — casar por igualdade exata perde os dois.
    sem_acento = lambda do |txt|
      txt.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
    end
    indice_nome = {}
    Item.pluck(:id, :name).each { |id, n| indice_nome[sem_acento.call(n)] ||= id }

    # Referências a itens do catálogo que a planilha escreve por outro nome.
    apelidos_catalogo = {
      'pocao de cura maior' => 'Cura Maior',
      'agua benta' => 'Agua Benta',
    }.freeze

    # ── 1. Matérias-primas ────────────────────────────────────────────────────
    materiais = seed['materiais'].map do |m|
      props = { 'unit' => m['unit'] }
      props['note'] = m['note'] if m['note']
      props['needs_review'] = m['needs_review'] if m['needs_review']
      { api_index: m['api_index'], name: m['name'], kind: 'material',
        category: m['category'], value_gp: m['value_gp'], source: m['source'], props: props }
    end
    bases.each do |categoria, linhas|
      linhas.each do |l|
        idx = "mat-#{l['name'].parameterize}"
        materiais << { api_index: idx, name: l['name'], kind: 'material', category: categoria,
                       value_gp: l['value_gp'], source: 'PHB/DMG', props: { 'unit' => l['unit'] } }
      end
    end

    materiais.each do |attrs|
      item = Item.find_by(api_index: attrs[:api_index])
      if item
        # Preserva o que o mestre editou: só completa o que está vazio, e nunca
        # sobrescreve um preço que ele definiu para um material `needs_review`.
        mudou = {}
        mudou[:name]     = attrs[:name]     if item.name.blank?
        mudou[:category] = attrs[:category] if item.category.blank?
        mudou[:value_gp] = attrs[:value_gp] if item.value_gp.blank? && attrs[:value_gp]
        mudou[:props]    = item.props.to_h.merge(attrs[:props]) if item.props.to_h != attrs[:props]
        next if mudou.empty?

        item.update!(mudou) unless dry
        stats[:materiais_atualizados] += 1
      else
        Item.create!(attrs) unless dry
        stats[:materiais_criados] += 1
      end
    end

    # ── 2. Produtos ───────────────────────────────────────────────────────────
    # Casa por api_index e, se não achar, por NOME normalizado: os ~5 produtos
    # já catalogados (Poção de Cura, Sopro de Fogo...) não podem duplicar.
    por_nome = indice_nome

    seed['produtos'].each do |p|
      item = Item.find_by(api_index: p['api_index'])
      item ||= Item.find_by(id: por_nome[sem_acento.call(p['name'])])

      props = { 'appearance' => p['appearance'] }.compact
      if item
        mudou = {}
        mudou[:description] = p['description'] if item.description.blank? && p['description']
        mudou[:rarity]      = p['rarity']      if item.rarity.blank? && p['rarity']
        mudou[:value_gp]    = p['value_gp']    if item.value_gp.blank? && p['value_gp']
        mudou[:props]       = item.props.to_h.merge(props) if props.any?
        item.update!(mudou) if mudou.any? && !dry
        stats[:produtos_reaproveitados] += 1
      else
        item = Item.create!(api_index: p['api_index'], name: p['name'], kind: p['kind'],
                            category: p['category'], rarity: p['rarity'],
                            value_gp: p['value_gp'], description: p['description'],
                            source: 'Manual do Alquimista (Duoin)', props: props) unless dry
        stats[:produtos_criados] += 1
      end
      next if dry || item.nil?

      # ── 3. Receita ──────────────────────────────────────────────────────────
      r = p['recipe']
      receita = CraftingRecipe.find_or_initialize_by(result_item_id: item.id)
      receita.assign_attributes(craft: r['craft'], dc: r['dc']&.to_i, days: r['days'],
                               craft_cost_gp: r['craft_cost_gp'],
                               processes: Array(r['processes']),
                               source: 'Manual do Alquimista (Duoin)')
      # `previously_new_record?` só existe do Rails 7 em diante; aqui é 6.0.
      era_nova = receita.new_record?
      receita.save!
      stats[era_nova ? :receitas_criadas : :receitas_atualizadas] += 1

      # Reescreve os ingredientes: a receita é a lista INTEIRA, e um import
      # incremental deixaria ingrediente velho pendurado se a planilha mudasse.
      receita.ingredients.destroy_all
      r['ingredients'].each_with_index do |ing, pos|
        attrs = { quantity: ing['quantidade'], unit: ing['unidade'],
                  alternative_group: ing['grupo_alternativa'], position: pos }
        case ing['tipo']
        when 'material', 'item'
          procurado = apelidos_catalogo[sem_acento.call(ing['nome'])] || ing['nome']
          alvo = Item.find_by(api_index: "mat-#{procurado.parameterize}") ||
                 Item.find_by(id: indice_nome[sem_acento.call(procurado)])
          if alvo.nil?
            # ⚠️ NÃO descartar: um ingrediente sumido deixa a receita incompleta
            # e ninguém percebe. Vira texto livre, que aparece na ficha e no
            # relatório do import.
            attrs[:raw_text] = ing['nome']
            stats[:ingredientes_sem_alvo] += 1
            warn "  ⚠️ sem item no catálogo (virou texto): #{ing['nome']} (em #{p['name']})"
          else
            attrs[:ingredient_item] = alvo
          end
        when 'magia'
          magia = Spell.where('lower(name) = ?', ing['nome'].to_s.downcase.strip).first
          if magia.nil?
            # Vira texto livre em vez de sumir: a receita continua legível.
            attrs[:raw_text] = "Magia: #{ing['nome']}"
            stats[:magias_nao_resolvidas] += 1
          else
            attrs[:spell] = magia
          end
        else
          attrs[:raw_text] = ing['nome']
          attrs[:is_choice] = true if ing['nome'].to_s.include?('Componente Extra')
        end
        receita.ingredients.create!(attrs)
        stats[:ingredientes] += 1
      end
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-28s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
