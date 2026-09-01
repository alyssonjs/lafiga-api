# Irmao do `dnd:fix_armor_kind_weapons`, para o outro lado do mesmo lixo de
# importacao: itens gravados como `kind: armor` com props VAZIAS que sao
# ARMADURA ou ESCUDO de verdade — e portanto nao dao CA nenhuma hoje.
#
#   bundle exec rake dnd:fix_armor_kind_armors                  # DRY RUN
#   APPLY=1 bundle exec rake dnd:fix_armor_kind_armors          # aplica
#   MAP="276=chain-mail,279=leather" APPLY=1 rake ...           # casa a mao
#
# ## Duas formas, porque sao dois `kind` diferentes
#
# ESCUDO: `kind: shield` + `props.ac_bonus`. Detectado pelo NOME — e a unica
# regra automatica segura aqui, porque no 5e TODO escudo da +2 de CA,
# independentemente de material: "Escudo de Madeira" e "Escudo M." sao os
# mesmos +2. Nao ha o que adivinhar.
#
# ARMADURA: `kind: armor` + `props.ac_base`/`dex_cap`/`str_req`/`stealth_dis`,
# copiados da armadura CANONICA casada por nome, apelido ou api_index.
#
# ⚠️ NAO adivinha o resto. "malha" pode ser camisao (CA 13) ou cota (CA 16) —
# tres pontos de CA de diferenca decididos por um palpite meu. "Armadura",
# "Roupas + couro" e "Armadura de coura de marmota +2" tem o mesmo problema, e
# ROUPA nao e armadura nenhuma (CA 10 + DES). Todos saem na lista, e o `MAP=`
# resolve os que o Mestre quiser em um comando.
namespace :dnd do
  desc 'ROUPA nao e armadura: vira kind=gear com peso/preco da roupa comum. APPLY=1 aplica.'
  task fix_clothing_kind: :environment do
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')

    # ⚠️ Nome que menciona MATERIAL DE ARMADURA fica de fora: "Roupas + couro" e
    # "Cota de malha + roupa" sao armadura COM roupa junto — vira-las em `gear`
    # apagaria a chance de darem CA, que e o oposto do conserto.
    material = /couro|malha|placa|peles|brunea|talas|acolchoad|anei|escama/i

    base = Item.find_by(kind: 'gear', api_index: 'roupas-comuns')
    alvos = Item.where(kind: 'armor').select do |i|
      (i.props || {})['ac_base'].blank? &&
        i.name.to_s.match?(/roupa/i) &&
        !i.name.to_s.match?(material)
    end
    excluidos = Item.where(kind: 'armor').select do |i|
      (i.props || {})['ac_base'].blank? && i.name.to_s.match?(/roupa/i) && i.name.to_s.match?(material)
    end

    alvos.sort_by(&:id).each do |item|
      puts format('  #%-5d %-34s -> gear (%s kg, %s po) em %d linha(s)', item.id, item.name.to_s[0, 34],
                  (item.weight_kg || base&.weight_kg).inspect, (item.value_gp || base&.value_gp).inspect,
                  SheetItem.where(item_id: item.id).count)
      next unless aplicar

      item.update!(
        kind: 'gear',
        weight_kg: item.weight_kg || base&.weight_kg,
        value_gp: item.value_gp || base&.value_gp,
      )
    end

    unless excluidos.empty?
      puts
      puts "== DEIXADOS DE FORA (#{excluidos.size}) — tem material de ARMADURA no nome =="
      excluidos.each { |i| puts format('  #%-5d %-34s (use a rake de armadura)', i.id, i.name.to_s[0, 34]) }
    end

    puts
    puts aplicar ? "OK: #{alvos.size} roupa(s) viraram equipamento." : "Seriam convertidas #{alvos.size}."
  end


  desc 'Da CA a escudo/armadura gravados como armor sem props. APPLY=1 aplica; MAP="id=indice,..." casa a mao.'
  task fix_armor_kind_armors: :environment do
    require 'active_support/core_ext/string'
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')

    normalizar = ->(s) { s.to_s.downcase.parameterize.tr('-', ' ').strip }

    # Indice canonico de ARMADURAS: so entram itens que ja tem `ac_base`.
    canonico = {}
    Item.where(kind: 'armor').each do |base|
      props = base.props || {}
      next if props['ac_base'].blank?

      [base.api_index, base.name, *Array(props['aliases'])].compact.each do |chave|
        canonico[normalizar.call(chave)] = base
      end
    end

    escudo_base = Item.find_by(kind: 'shield', api_index: 'shield')
    manual = ENV['MAP'].to_s.split(',').map { |par| par.split('=', 2) }
                       .each_with_object({}) { |(id, idx), h| h[id.to_s.strip.to_i] = idx.to_s.strip }

    suspeitos = Item.where(kind: 'armor').select { |i| (i.props || {})['ac_base'].blank? }
    escudos = []
    armaduras = []
    pendentes = []

    suspeitos.sort_by(&:id).each do |item|
      nome = normalizar.call(item.name)

      # ESCUDO pelo nome — regra do livro, nao palpite.
      if manual[item.id].blank? && nome.split.include?('escudo')
        escudos << item
        next
      end

      chave =
        if manual[item.id]
          normalizar.call(manual[item.id])
        else
          nome.gsub(/\b(x\s*)?\d+\b/, '').gsub(/\+\s*\d*/, '').squeeze(' ').strip
        end
      base = canonico[chave] || canonico[chave.singularize]
      base ? armaduras << [item, base] : pendentes << item
    end

    if aplicar
      escudos.each do |item|
        props = (escudo_base&.props || { 'ac_bonus' => 2, 'cost_cp' => 1000 }).dup
        item.update!(
          kind: 'shield',
          props: props.except('aliases'),
          weight_kg: item.weight_kg || escudo_base&.weight_kg,
          value_gp: item.value_gp || escudo_base&.value_gp,
        )
      end
      armaduras.each do |item, base|
        props = (base.props || {}).except('aliases')
        item.update!(
          kind: 'armor',
          props: props,
          category: item.category.presence || base.category,
          weight_kg: item.weight_kg || base.weight_kg,
          value_gp: item.value_gp || base.value_gp,
        )
      end
    end

    puts "== ESCUDOS (#{escudos.size}) — +2 de CA =="
    escudos.each { |i| puts format('  #%-5d %-34s em %d linha(s)', i.id, i.name.to_s[0, 34], SheetItem.where(item_id: i.id).count) }
    puts
    puts "== ARMADURAS casadas (#{armaduras.size}) =="
    armaduras.each do |item, base|
      puts format('  #%-5d %-30s -> %-18s CA %s', item.id, item.name.to_s[0, 30], base.api_index, (base.props || {})['ac_base'])
    end
    puts
    puts "== PRECISAM DE DECISAO (#{pendentes.size}) =="
    puts '   (use MAP="ID=indice,..." — ou edite no compendio; ROUPA nao e armadura)'
    pendentes.each { |i| puts format('  #%-5d %-34s em %d linha(s)', i.id, i.name.to_s[0, 34], SheetItem.where(item_id: i.id).count) }
    puts
    total = escudos.size + armaduras.size
    puts aplicar ? "OK: #{total} corrigido(s) (#{escudos.size} escudo, #{armaduras.size} armadura)." : "Seriam corrigidos #{total}."
  end
end
