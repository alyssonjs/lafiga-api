# frozen_string_literal: true

# Semeia a tabela EQUIPAMENTO do PHB (pág. 150) — 99 itens.
#
#   bin/rails dnd:seed_phb_gear            # cria/repara
#   DRY_RUN=1 bin/rails dnd:seed_phb_gear  # só relata
#
# Por que existe: o catálogo tinha 12 itens `gear` no `equipment.yml` (quase
# todos focos e munição). Mochila, Acendedor, Corda de cânhamo e Tigela
# simplesmente NÃO EXISTIAM — e 28 das 48 linhas dos pacotes apontavam para
# eles. Sem esta base não há a que ligar.
#
# ⚠️ O peso do PHB pt-BR já é em KG (a edição em inglês é lb). O banco é
# canônico em kg: não se converte nada, converter dobraria tudo.
#
# Repara em vez de duplicar, mas SÓ pelo mapa explícito do seed
# (`repair_index`): reparar por semelhança fundiria "Livro" com "Livro
# yuan-ti". Item existente que não está no mapa fica intocado, e o do PHB é
# criado ao lado — o mestre funde depois se quiser.
namespace :dnd do
  desc 'Semeia a tabela Equipamento do PHB (99 itens)'
  task seed_phb_gear: :environment do
    dry = ENV['DRY_RUN'].present?
    seed = JSON.parse(File.read(Rails.root.join('db', 'data', 'phb_gear_seed.json')))
    stats = Hash.new(0)
    puts "== seed_phb_gear #{'(DRY RUN)' if dry} =="

    seed.each do |s|
      # 1. o item do PHB já existe pelo api_index canônico?
      item = Item.find_by(api_index: s['api_index'])
      # 2. senão, existe com nome torto declarado no mapa de reparos?
      alvo_reparo = s['repair_index'].present? ? Item.find_by(api_index: s['repair_index']) : nil
      item ||= alvo_reparo

      if item.nil?
        unless dry
          Item.create!(api_index: s['api_index'], name: s['name'], kind: s['kind'],
                       category: s['category'], value_gp: s['value_gp'],
                       weight_kg: s['weight_kg'], source: s['source'])
        end
        stats[:criados] += 1
        next
      end

      mudou = {}
      # Preço e peso do LIVRO preenchem o que está vazio — é justamente o que
      # falta nos homebrew (todos com value_gp/weight_kg nil, por isso a carga
      # nunca fechou). Valor já definido pelo mestre NÃO é sobrescrito.
      mudou[:value_gp]  = s['value_gp']  if item.value_gp.blank?
      mudou[:weight_kg] = s['weight_kg'] if item.weight_kg.blank?
      mudou[:source]    = s['source']    if item.source.blank?
      # `kind` errado declarado (ex.: estrepe catalogado como `armor`).
      mudou[:kind] = s['fix_kind'] if s['fix_kind'].present? && item.kind != s['fix_kind']
      # ⚠️ Preenche category VAZIA: sem ela o item some de toda aba (o balde
      # `:gear` usa `where.not`, NULL-unsafe). Categoria já definida pelo
      # mestre não é tocada.
      mudou[:category] = s['category'] if s['category'].present? && item.category.blank?

      if mudou.any?
        item.update!(mudou) unless dry
        stats[alvo_reparo ? :reparados_nome_torto : :completados] += 1
        puts "  ~ #{item.name} → #{mudou.keys.join(', ')}" if alvo_reparo
      else
        stats[:ja_ok] += 1
      end
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-24s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
