# Tenta casar cada suspeito com uma arma CANÔNICA do catálogo (mesma tabela que
# o app usa), sem inventar número nenhum.
require 'active_support/core_ext/string'
norm = ->(s) { s.to_s.downcase.parameterize.tr('-', ' ').strip }

tabela = EquipmentRules::WEAPON_TABLE
canon = {}
tabela.each do |idx, row|
  it = Item.find_by(api_index: idx)
  canon[norm.call(idx)] = [idx, row]
  canon[norm.call(it.name)] = [idx, row] if it
  Array((it&.props || {})['aliases']).each { |a| canon[norm.call(a)] = [idx, row] }
end

suspeitos = Item.where(kind: 'armor').select { |i| (i.props || {})['ac_base'].blank? }
casou, nao = [], []
suspeitos.each do |i|
  base = norm.call(i.name)
  # remove sufixos de quantidade/bônus que o DM digitou: "Azagaias x8", "(10)", "+1"
  base = base.gsub(/\b(x\s*)?\d+\b/, '').gsub(/\+\s*\d*/, '').squeeze(' ').strip
  hit = canon[base] || canon[base.singularize] || canon[base.split.first.to_s]
  (hit ? casou : nao) << [i, hit]
end

puts "== CASAM com arma canônica (#{casou.size}) =="
casou.each { |i, h| puts format('  #%-5d %-32s -> %-18s %s', i.id, i.name.to_s[0,32], h[0], h[1][:damage_die]) }
puts
puts "== NÃO casam (#{nao.size}) =="
nao.each { |i, _| puts format('  #%-5d %-32s linhas=%d', i.id, i.name.to_s[0,32], SheetItem.where(item_id: i.id).count) }
