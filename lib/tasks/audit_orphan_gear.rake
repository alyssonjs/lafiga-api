# TRIAGEM dos itens `gear` sem categoria — RELATORIO, nunca escreve.
#
#   bundle exec rake dnd:audit_orphan_gear
#
# ## Por que existe
#
# O balde `:gear` usa `where.not(category: [...])`, que e NULL-unsafe (`NOT IN`
# com NULL nunca casa): ~213 itens com `category: nil` NAO aparecem na aba
# Equipamentos. Consertar o filtro e uma linha — mas antes de conserta-lo,
# alguem precisa OLHAR o que ele estava escondendo.
#
# Medido: 211 dos 213 nao tem descricao NEM custo, e 191 estao em bolsa de
# jogador. Sao entradas de mesa ("Alguma coisa", "bolsa PO"), nao itens de
# catalogo. O bug funciona hoje como filtro de curadoria acidental: corrigi-lo
# sem faxina despeja 213 entradas desleixadas no compendio.
#
# Este rake separa o que da para agir:
#   - ORFAOS      nao estao em bolsa nenhuma — apagar e barato e seguro
#   - DUPLICADOS  mesmo nome normalizado, varias entradas
#   - EM USO      estao em bolsa; renomear/classificar, nao apagar
namespace :dnd do
  desc 'Relata os itens gear sem categoria, separados por acao possivel'
  task audit_orphan_gear: :environment do
    todos = Item.where(kind: 'gear', category: nil).to_a
    em_uso_ids = SheetItem.where(item_id: todos.map(&:id)).distinct.pluck(:item_id).to_set

    orfaos, em_uso = todos.partition { |i| !em_uso_ids.include?(i.id) }

    def norm(nome)
      nome.to_s.downcase.strip.gsub(/\s+/, ' ').gsub(/[^a-z0-9 ]/, '')
    end

    duplicados = todos.group_by { |i| norm(i.name) }.select { |_, v| v.size > 1 }

    puts "[dnd:audit_orphan_gear] #{todos.size} itens `gear` sem categoria (invisiveis na aba)"
    puts

    puts "== ORFAOS (#{orfaos.size}) — em bolsa nenhuma, apagar e seguro:"
    orfaos.sort_by(&:name).first(40).each { |i| puts "   #{i.api_index.ljust(40)} #{i.name.inspect}" }
    puts "   ... e mais #{orfaos.size - 40}" if orfaos.size > 40
    puts

    puts "== DUPLICADOS por nome (#{duplicados.size} grupos):"
    duplicados.sort_by { |k, _| k }.first(15).each do |nome, itens|
      usados = itens.count { |i| em_uso_ids.include?(i.id) }
      puts "   #{nome.inspect}: #{itens.size} entradas (#{usados} em uso) -> #{itens.map(&:api_index).join(', ')}"
    end
    puts "   ... e mais #{duplicados.size - 15} grupos" if duplicados.size > 15
    puts

    puts "== EM USO (#{em_uso.size}) — renomear/classificar no admin, NAO apagar:"
    em_uso.sort_by(&:name).first(20).each do |i|
      n = SheetItem.where(item_id: i.id).count
      puts "   #{i.api_index.ljust(40)} #{i.name.inspect} (#{n} bolsa(s))"
    end
    puts "   ... e mais #{em_uso.size - 20}" if em_uso.size > 20
    puts
    puts "Depois da faxina: trocar o `where.not` do balde :gear por IS DISTINCT FROM"
    puts "(equipment_controller.rb) para os itens legitimos voltarem a aparecer."
  end
end
