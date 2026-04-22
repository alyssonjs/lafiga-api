# Backfill de SheetItem.item_id para registros antigos.
#
# Por que existe:
#   Antes do callback `before_validation :resolve_catalog_item` ser adicionado
#   ao SheetItem, todos os 803 itens persistidos foram salvos com
#   `item_id IS NULL` — sem ligacao com o catalogo Item. Isso impede que a
#   ficha mostre props de combate (peso, dano, custo), gera duplicatas no DB
#   e quebra qualquer feature que cruze SheetItem ↔ Item (ex.: pagina
#   /items, busca por inventario, modificadores derivados de itens).
#
# O que faz:
#   - SheetItem.where(item_id: nil) → invoca ItemResolver.resolve(name:, category:)
#   - quando resolver retorna Item, popula `item_id` e `item_index` via
#     update_columns (sem disparar validations/callbacks pra evitar trigger
#     do `validate_equipment_proficiency` em items historicos)
#   - quando nao resolve (nome vazio, "2.0", etc.), conta como skipped e segue
#
# Idempotente: rodar varias vezes nao causa duplicatas no Item (ItemResolver
# usa find_or_create_by!).
#
# Uso:
#   docker exec lafiga_api bundle exec rails sheet_items:backfill_item_id
#   docker exec lafiga_api bundle exec rails sheet_items:backfill_item_id DRY_RUN=1
#   docker exec lafiga_api bundle exec rails sheet_items:backfill_item_id SHEET_ID=13888
namespace :sheet_items do
  desc 'Resolve item_id em SheetItems existentes via ItemResolver, criando Items que faltam no catalogo.'
  task backfill_item_id: :environment do
    dry_run  = ENV['DRY_RUN'].to_s == '1'
    sheet_id = ENV['SHEET_ID'].presence&.to_i

    scope = SheetItem.where(item_id: nil)
    scope = scope.where(sheet_id: sheet_id) if sheet_id

    resolver = ItemResolver.new
    counts = Hash.new(0)
    skipped_examples = []
    items_before = Item.count

    scope.find_each(batch_size: 200) do |si|
      counts[:total] += 1

      name = si.item_name.to_s.strip
      if name.blank? || name =~ /\A\d+(\.\d+)?\z/
        counts[:skipped_invalid] += 1
        skipped_examples << "sheet=#{si.sheet_id} si=#{si.id} name=#{si.item_name.inspect}"
        next
      end

      item = resolver.resolve(name: name, category: si.category)
      unless item
        counts[:unresolved] += 1
        skipped_examples << "sheet=#{si.sheet_id} si=#{si.id} name=#{si.item_name.inspect}"
        next
      end

      counts[:resolved] += 1
      next if dry_run

      si.update_columns(item_id: item.id, item_index: si.item_index.presence || item.api_index)
      counts[:updated] += 1
    end

    items_after = Item.count

    puts '=== SheetItem item_id backfill ==='
    puts "DRY_RUN: #{dry_run}"
    puts "SHEET_ID: #{sheet_id || 'all'}"
    counts.each { |k, v| puts "  #{k.to_s.ljust(18)} #{v}" }
    puts "  items_created      #{items_after - items_before}"
    if skipped_examples.any?
      puts "\n--- Skipped/unresolved examples (primeiros 30) ---"
      skipped_examples.first(30).each { |line| puts "  #{line}" }
      puts "  ... +#{skipped_examples.size - 30} more" if skipped_examples.size > 30
    end
  end
end
