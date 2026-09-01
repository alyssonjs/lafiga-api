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
      novo = {
        kind: 'weapon',
        props: props.except('aliases'),
        category: item.category.presence || base_item&.category || row[:category],
        weight_kg: item.weight_kg || base_item&.weight_kg,
        value_gp: item.value_gp || base_item&.value_gp,
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

    puts
    puts aplicar ? "OK: #{corrigidos.size} item(ns) com estatistica." : "Seriam corrigidos #{corrigidos.size}."
  end
end
