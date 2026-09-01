# Conserta itens de catalogo gravados com `kind: armor` e props VAZIAS —
# armas (e armaduras) que nasceram de importacao de ficha e ficaram sem
# estatistica nenhuma: sem dado de dano nao ha o que exibir NEM o que rolar.
#
#   bundle exec rake dnd:fix_armor_kind_weapons                 # DRY RUN
#   APPLY=1 bundle exec rake dnd:fix_armor_kind_weapons         # aplica os que casam
#   MAP="232=scimitar,347=crossbow-light" APPLY=1 rake ...      # casa a mao
#
# ## O que ele faz, e o que NAO faz
#
# CASA por nome (normalizado, sem o "x8"/"(10)"/"+1" que o DM digitou) contra a
# tabela CANONICA de armas — `api_index`, nome do item e `aliases`. Quando casa,
# copia dali dado de dano, propriedades, categoria, peso e preco.
#
# ⚠️ NAO adivinha. "Cimitrra", "Besque leve", "Espadas longa" sao erros de
# digitacao evidentes, mas corrigi-los seria eu escolhendo a arma no lugar do
# Mestre — e "Malho", "Picareta", "Sai", "Tonfa" nem tem equivalente no PHB.
# Esses saem na LISTA do relatorio, e o `MAP=` existe para o Mestre resolve-los
# em UM comando em vez de 44 edicoes no formulario.
#
# ⚠️ O nome do item NAO muda: "Adaga de Sangue" continua "Adaga de Sangue" —
# so ganha as estatisticas da adaga. O que e magico nele vive nos efeitos.
namespace :dnd do
  desc 'Da estatisticas a itens kind=armor sem props (armas de importacao). APPLY=1 aplica; MAP="id=indice,..." casa a mao.'
  task fix_armor_kind_weapons: :environment do
    require 'active_support/core_ext/string'
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')

    normalizar = ->(s) { s.to_s.downcase.parameterize.tr('-', ' ').strip }

    # Indice canonico: api_index + nome + aliases de cada arma da tabela.
    canonico = {}
    EquipmentRules::WEAPON_TABLE.each do |idx, row|
      registro = Item.find_by(api_index: idx)
      canonico[normalizar.call(idx)] = [idx, row, registro]
      canonico[normalizar.call(registro.name)] = [idx, row, registro] if registro
      Array((registro&.props || {})['aliases']).each do |apelido|
        canonico[normalizar.call(apelido)] = [idx, row, registro]
      end
    end

    manual = ENV['MAP'].to_s.split(',').map { |par| par.split('=', 2) }
                       .each_with_object({}) { |(id, idx), h| h[id.to_s.strip.to_i] = idx.to_s.strip }

    suspeitos = Item.where(kind: 'armor').select { |i| (i.props || {})['ac_base'].blank? }
    corrigidos = []
    pendentes = []

    # PASSE DE REPARO: item já convertido cujas props têm peso/preço mas a
    # COLUNA ficou nula (rodadas anteriores desta rake, antes de ela ler as
    # props). Não precisa casar nome nenhum — o dado já está no próprio item.
    reparados = Item.where(kind: 'weapon').select do |i|
      pr = i.props || {}
      (i.weight_kg.nil? && pr['weight_kg'].present?) ||
        (i.value_gp.nil? && pr['cost_cp'].present?)
    end
    reparados.each do |item|
      pr = item.props || {}
      next unless aplicar

      item.update!(
        weight_kg: item.weight_kg || pr['weight_kg'],
        value_gp: item.value_gp || (pr['cost_cp'].present? ? (pr['cost_cp'].to_f / 100) : nil),
      )
    end

    suspeitos.sort_by(&:id).each do |item|
      chave =
        if manual[item.id]
          normalizar.call(manual[item.id])
        else
          base = normalizar.call(item.name)
          # tira quantidade e bonus que o Mestre digitou no NOME
          base.gsub(/\b(x\s*)?\d+\b/, '').gsub(/\+\s*\d*/, '').squeeze(' ').strip
        end

      achado = canonico[chave] || canonico[chave.singularize] || canonico[chave.split.first.to_s]
      unless achado
        pendentes << item
        next
      end

      idx, row, base_item = achado
      props = (base_item&.props || {}).presence || row.stringify_keys
      # ⚠️ PESO e PREÇO vêm das props quando não há registro-base: a arma
      # canônica nem sempre tem `Item` próprio (escimitarra, espada-longa,
      # besta-pesada…) e aí só a linha da tabela tem o dado. A CARGA lê a
      # COLUNA, não as props — sem isto o item pesa zero na bolsa.
      peso = item.weight_kg || base_item&.weight_kg || props['weight_kg']
      centavos = props['cost_cp']
      preco = item.value_gp || base_item&.value_gp ||
              (centavos.present? ? (centavos.to_f / 100) : nil)
      novo = {
        kind: 'weapon',
        props: props.except('aliases'),
        category: item.category.presence || base_item&.category || row[:category],
        weight_kg: peso,
        value_gp: preco,
      }
      corrigidos << [item, idx, novo]
      item.update!(novo) if aplicar
    end

    puts "== CORRIGIDOS (#{corrigidos.size}) =="
    corrigidos.each do |item, idx, novo|
      puts format('  #%-5d %-34s -> %-16s dano=%s', item.id, item.name.to_s[0, 34], idx, novo[:props]['damage_die'])
    end

    puts
    puts "== PRECISAM DE DECISAO (#{pendentes.size}) =="
    puts '   (use MAP="ID=indice-da-arma,..." — ou edite no compendio)'
    pendentes.each do |item|
      linhas = SheetItem.where(item_id: item.id).count
      puts format('  #%-5d %-34s em %d linha(s) de ficha', item.id, item.name.to_s[0, 34], linhas)
    end

    unless reparados.empty?
      puts
      puts "== PESO/PRECO repostos na coluna (#{reparados.size}) =="
      reparados.each { |i| puts format('  #%-5d %-34s %s kg', i.id, i.name.to_s[0, 34], (i.props || {})['weight_kg']) }
    end

    puts
    puts aplicar ? "OK: #{corrigidos.size} item(ns) com estatistica, #{reparados.size} com peso/preco reposto." : "Seriam corrigidos #{corrigidos.size} (+#{reparados.size} peso/preco)." 
  end
end
