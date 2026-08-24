# Converte itens do catalogo em PERGAMINHO DE MAGIA (`kind: consumable` +
# `category: scroll`), preservando os `sheet_items` que ja apontam para eles.
#
#   bundle exec rake dnd:convert_scrolls                       # LISTA candidatos
#   INDEXES=a,b APPLY=1 bundle exec rake dnd:convert_scrolls   # converte SO esses
#
# Por que a lista e EXPLICITA e nao por nome: entre os candidatos ha papel e
# item de enredo ("Um pergaminho com uma profecia", "pergaminho molhado").
# Converte-los daria a eles um botao "Usar Pergaminho" que APAGA o item da
# bolsa — destrutivo e errado. Quem sabe quais sao de magia e o mestre.
#
# `kind` e imutavel pelo editor de proposito; por isso a conversao vive aqui.
namespace :dnd do
  desc 'Lista candidatos a pergaminho; INDEXES=a,b APPLY=1 converte os escolhidos'
  task convert_scrolls: :environment do
    apply = ENV['APPLY'].present?
    escolhidos = ENV['INDEXES'].to_s.split(',').map(&:strip).reject(&:empty?)

    if escolhidos.empty?
      candidatos = Item.where("LOWER(name) LIKE ?", '%pergaminho%')
                       .where.not(kind: 'consumable')
                       .order(:name)
      puts "[dnd:convert_scrolls] #{candidatos.count} candidato(s). Nenhum INDEXES informado — nada foi alterado."
      puts '  Escolha os que sao PERGAMINHO DE MAGIA e rode com:'
      puts '    INDEXES=idx1,idx2 APPLY=1 bundle exec rake dnd:convert_scrolls'
      candidatos.each do |i|
        usos = SheetItem.where(item_index: i.api_index).count
        puts "    #{i.api_index.ljust(38)} #{i.name.inspect} (kind=#{i.kind}, em #{usos} bolsa(s))"
      end
      next
    end

    convertidos = []
    pulados = []
    escolhidos.each do |idx|
      item = Item.find_by(api_index: idx)
      next pulados << "#{idx}: nao existe" if item.nil?
      if item.kind == 'consumable' && item.category == 'scroll'
        next pulados << "#{idx}: ja e pergaminho"
      end

      usos = SheetItem.where(item_index: item.api_index).count
      convertidos << "#{idx} (#{item.kind} -> consumable/scroll, #{usos} bolsa(s) preservada(s))"
      # `sheet_items` apontam por `item_index`, que NAO muda: o vinculo segue.
      item.update!(kind: 'consumable', category: 'scroll') if apply
    end

    puts "[dnd:convert_scrolls]#{' DRY RUN —' unless apply} #{convertidos.size} convertido(s), #{pulados.size} pulado(s)"
    convertidos.each { |c| puts "  convertido: #{c}" }
    pulados.each     { |p| puts "  pulado: #{p}" }
    puts '  (nada foi gravado — repita com APPLY=1)' unless apply
  end
end
