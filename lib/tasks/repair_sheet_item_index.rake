# frozen_string_literal: true

# Realinha `sheet_items.item_index` ao `api_index` do item que a linha JÁ
# referencia por `item_id`.
#
#   bin/rails dnd:repair_sheet_item_index            # aplica
#   DRY_RUN=1 bin/rails dnd:repair_sheet_item_index  # só relata
#
# O front fala em ID PREFIXADO por convenção própria (`wp-*`, `ar-*`, `gi-*`,
# `kit-*`, derivados do api_index) e esse id vazava para o banco ao persistir a
# linha. Resultado: `item_index` apontando para um índice que NÃO existe como
# `Item.api_index`. Hoje não quebra porque a resolução acontece pela associação
# `item_id` — mas qualquer código que resolva por índice erra, e essa é a mesma
# classe de divergência que já custou caro em armadura e proficiência.
#
# ⚠️ A regra é "reescrever pelo `item_id`", NUNCA "cortar o prefixo":
# existem 24 itens LEGÍTIMOS cujo `api_index` começa com `kit-` (kit-refeicao,
# kit-herbalismo, kit-sos-x3…). Cortar a string quebraria 27 linhas corretas.
# Casar pela associação acerta os quatro prefixos sem adivinhar nada.
namespace :dnd do
  desc 'Realinha sheet_items.item_index ao api_index do item referenciado'
  task repair_sheet_item_index: :environment do
    dry = ENV['DRY_RUN'].present?
    puts "== repair_sheet_item_index #{'(DRY RUN)' if dry} =="

    corrigidas = 0
    por_par = Hash.new(0)

    SheetItem.where.not(item_id: nil).includes(:item).find_each do |si|
      item = si.item
      next if item.nil? || si.item_index == item.api_index

      por_par[[si.item_index, item.api_index]] += 1
      si.update_columns(item_index: item.api_index) unless dry
      corrigidas += 1
    end

    por_par.sort_by { |_, v| -v }.each do |(antes, depois), n|
      puts format('  ~ %-26s → %-24s (%d)', antes, depois, n)
    end

    puts "\n== resultado =="
    puts format('  %-22s %d', 'linhas_realinhadas', corrigidas)
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
