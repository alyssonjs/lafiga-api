# frozen_string_literal: true

# Tira de `consumable` os três itens que caíam no filtro "Outros" da aba
# Consumíveis — e que, olhados um a um, não eram consumíveis.
#
#   bin/rails dnd:reclassify_orphan_consumables            # aplica
#   DRY_RUN=1 bin/rails dnd:reclassify_orphan_consumables  # só relata
#
# Os três eram CASCAS VAZIAS: sem descrição, valor, peso, props ou MagicItem —
# criados pelo `ItemResolver` a partir do nome escrito numa ficha. Como o
# catálogo não dizia nada sobre eles, o destino de cada um foi decidido pelo
# mestre (27/08), não deduzido por heurística.
#
# ⚠️ Nenhum vira sub-tipo de consumível: um amuleto se veste e um coração de
# elemental é insumo. Classificá-los "dentro" de Consumíveis só para esvaziar
# o filtro "Outros" teria dado ao amuleto um botão "Consumir".
namespace :dnd do
  desc 'Reclassifica os 3 consumíveis sem sub-tipo (decisão do mestre)'
  task reclassify_orphan_consumables: :environment do
    dry = ENV['DRY_RUN'].present?
    puts "== reclassify_orphan_consumables #{'(DRY RUN)' if dry} =="

    ALVOS = {
      # "Amu." = amuleto: veste-se no pescoço, não se gasta.
      'amu-furacao' => { kind: 'gear', category: 'amulet' },
      # Despojo de criatura → ingrediente de receita.
      'coracao-de-elemental-vento' => { kind: 'material', category: 'monster-part' },
      # Insumo de encantamento.
      'pedra-elemental-agua-x17' => { kind: 'material', category: 'arcane' },
    }.freeze

    stats = Hash.new(0)
    ALVOS.each do |idx, destino|
      it = Item.find_by(api_index: idx)
      next puts("  ⚠️ ausente: #{idx}") && stats[:ausentes] += 1 if it.nil?

      if it.kind == destino[:kind].to_s && it.category == destino[:category]
        stats[:ja_ok] += 1
        next
      end

      fichas = SheetItem.where(item_id: it.id).count
      puts format('  ~ %-32s %-12s → %s/%s (%d ficha(s))',
                  it.name.to_s[0, 32], it.kind, destino[:kind], destino[:category], fichas)
      it.update!(kind: destino[:kind], category: destino[:category]) unless dry
      stats[:reclassificados] += 1
    end

    # A contagem-no-NOME ("x17") é decisão do mestre: `x17` tanto pode ser 17
    # unidades como o nome da pedra. Só relatamos — mexer seria adivinhar.
    pedra = Item.find_by(api_index: 'pedra-elemental-agua-x17')
    if pedra
      puts "\n  [aviso] \"#{pedra.name}\" carrega a contagem no NOME; a linha de ficha diz " \
           "quantidade #{SheetItem.where(item_id: pedra.id).sum(:quantity)}. Só o mestre sabe qual manda."
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-20s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
