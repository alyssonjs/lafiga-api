# frozen_string_literal: true

namespace :dnd do
  desc 'Corrige a categoria de instrumentos musicais ja comprados (idempotente)'
  # `sheet_items.category` e TEXTO copiado do catalogo no momento da compra.
  # O alaude esteve catalogado como `armor` e o violino tambem: quem comprou
  # antes da correcao ficou com "Armas"/"Armaduras & Escudos" gravado, e o
  # instrumento aparecia EQUIPAVEL na bolsa — tratado como arma.
  #
  # O front ja tolera o texto velho (corrige pelo nome), mas o dado canonico
  # tambem tem de ficar certo: outros leitores usam a coluna crua.
  #
  # PHB cap. 5: instrumento musical e FERRAMENTA. Nao ha slot de instrumento.
  task repair_instrument_sheet_items: :environment do
    def fold(s) = s.to_s.strip.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase

    nomes = Item.where(kind: 'tool', category: 'instrument').pluck(:name).map { |n| fold(n) }.to_set
    if nomes.empty?
      puts '[dnd:repair_instrument_sheet_items] catalogo sem instrumentos — rode dnd:seed_phb_tools antes'
      next
    end

    # As categorias que fazem o item virar equipavel na bolsa.
    erradas = ['Armas', 'Armaduras', 'Armaduras & Escudos']
    corrigidos = 0
    ja_ok = 0

    SheetItem.where(category: erradas).find_each do |si|
      next unless nomes.include?(fold(si.item_name))

      antes = si.category
      si.update_columns(category: 'Itens Gerais', updated_at: Time.current)
      corrigidos += 1
      puts "  ficha #{si.sheet_id}: \"#{si.item_name}\" #{antes.inspect} -> \"Itens Gerais\""
    end

    SheetItem.find_each do |si|
      ja_ok += 1 if nomes.include?(fold(si.item_name)) && !erradas.include?(si.category.to_s)
    end

    puts "[dnd:repair_instrument_sheet_items] corrigidos=#{corrigidos} ja_ok=#{ja_ok}"
  end
end
