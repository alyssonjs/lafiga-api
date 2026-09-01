puts "=== Itens kind=armor SEM ac_base (props incompletas) ==="
suspeitos = Item.where(kind: 'armor').select { |i| (i.props || {})['ac_base'].blank? }
suspeitos.sort_by(&:id).each do |i|
  linhas = SheetItem.where(item_id: i.id)
  cats = linhas.map { |l| l.category.to_s }.uniq
  fichas = linhas.map(&:sheet_id).uniq
  puts format('  #%-5d %-38s cat=%-10s sub=%-12s peso=%-6s valor=%-8s props=%-4d | linhas=%d fichas=%s cat_ficha=%s',
              i.id, i.name.to_s[0, 38], i.category.inspect, i.sub_category.inspect,
              i.weight_kg.inspect, i.value_gp.inspect, (i.props || {}).size,
              linhas.count, fichas.inspect, cats.inspect)
end
puts "TOTAL: #{suspeitos.size}"
