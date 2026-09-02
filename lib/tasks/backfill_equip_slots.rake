# Carimba `props['equip_slot']` em todo item do CATALOGO que se equipa.
#
#   bundle exec rake dnd:backfill_equip_slots            # DRY RUN (padrao)
#   APPLY=1 bundle exec rake dnd:backfill_equip_slots    # aplica
#
# ## Por que existe
#
# O front decidia "onde isto se equipa" com ~40 regex de NOME espalhadas —
# e cada item de nome criativo era um bug: a bolsa nasceu inequipavel, o
# "Coldre de coxa" tambem (a regex procura "cinto"), armadura ja nasceu como
# arma. O leitor declarado JA tem precedencia no front; o que nunca houve foi
# ESCRITOR. Este rake roda a heuristica UMA ULTIMA VEZ, no servidor, e congela
# o resultado como declaracao. Depois dele, a regex vira fallback de item
# manual sem catalogo — deixa de segurar o mundo.
#
# ## Ordem de decisao (a mais estrutural primeiro)
#
#   1. KIND       — armor/shield/weapon/book/tool+instrument (0% nome)
#   2. CATEGORY   — peca de vestuario, bag, focus, instrument (0% nome)
#   3. PROPS      — recipiente de municao declarado, capacidade de bolsa
#   4. NOME       — so o `gear` sem categoria; saem numa secao "CONFIRA"
#                    propria no relatorio, porque e a heuristica congelando
#
# NAO recebe slot: material, consumable, treasure, ammunition (municao NUNCA
# equipa), magic_item (a identidade dele mora em MagicItem.sub_category, 98%
# declarada), vehicle_*/tack/pack/equipment (equipamento de aventura).
#
# Idempotente: nunca sobrescreve `equip_slot` ja presente.
namespace :dnd do
  desc 'Carimba equip_slot no catalogo (mata as regex de nome). APPLY=1 aplica.'
  task backfill_equip_slots: :environment do
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')

    # Peca declarada (category do vestuario) -> slot. Espelho do PIECE_TO_SLOT
    # do front (wardrobePropsPayload.ts).
    peca_para_slot = {
      'ring' => 'ring_left', 'earrings' => 'earrings',
      'necklace' => 'amulet', 'choker' => 'amulet', 'amulet' => 'amulet', 'locket' => 'amulet',
      'circlet' => 'helmet', 'helmet' => 'helmet',
      'mask' => 'face', 'goggles' => 'face',
      'bracelet_left' => 'bracelet_left', 'bracelet_right' => 'bracelet_right',
      'belt' => 'belt', 'belt_leg' => 'belt_leg_left',
      'gloves' => 'gloves', 'gauntlets' => 'gloves',
      'boots' => 'boots', 'anklet' => 'boots',
      'cloak' => 'cloak', 'brooch' => 'cloak',
    }.freeze

    normalizar = ->(s) { s.to_s.downcase.gsub(/[áàâã]/, 'a').gsub(/[éê]/, 'e').gsub(/[íî]/, 'i').gsub(/[óôõ]/, 'o').gsub(/[úû]/, 'u').gsub(/ç/, 'c') }

    # Nomes de instrumento (espelho do toolsCatalog do front) — usados so no
    # passe POR NOME.
    instrumentos = /\b(alaude|flauta|tambor|lira|harpa|gaita|viola|trombeta|corneta|pandeiro|ocarina|bandolim|citara|violino)\b/

    # Slot por NOME — a MESMA pergunta do `suggestedAccessorySlot` do front.
    slot_por_nome = lambda do |nome|
      t = normalizar.call(nome)
      return 'back'       if t =~ /\b(aljava|quiver)\b/
      # ⚠️ "bolsa PO"/"bolsa de moedas" e DINHEIRO, nao recipiente.
      return 'back'       if t =~ /\b(bolsa|mochila|sacola|backpack|alforje)\b/ && t !~ /\b(po|pp|pc|ppl|moeda)\b/
      return 'instrument' if t =~ instrumentos
      return 'helmet'     if t =~ /\b(elmo|capacete|chapeu|gorro|coroa|tiara|diadema|circlet|helm)\b/
      return 'face'       if t =~ /\b(mascara|oculos|goggles|lentes?)\b/
      return 'gloves'     if t =~ /\b(luvas?|manoplas?|gauntlet)\b/
      # ⚠️ PERNA antes do cinto generico: "Cinto de perna" contem "cinto", e a
      # regra errada mandaria o coldre para a CINTURA — o dry-run pegou.
      return 'belt_leg_left' if t =~ /cinto\s+d[ea]\s+(perna|coxa)|coldre/
      return 'belt'       if t =~ /\b(cinto|cinta|belt|cinturao)\b/
      return 'earrings'   if t =~ /\b(brincos?|piercing)\b/
      return 'bracelet_left' if t =~ /\b(braceletes?|pulseiras?|bangle)\b/
      return 'amulet'     if t =~ /\b(colar|amuleto|gargantilha|medalhao|relicario|pingente|talisma)\b/
      return 'cloak'      if t =~ /\b(manto|capa|capote|broche)\b/
      return 'boots'      if t =~ /\b(botas?|tornozeleira|sapatos?|sandalias?)\b/
      return 'ring_left'  if t =~ /\b(anel|aneis)\b/
      return 'main_hand'  if t =~ /\b(foco|totem|simbolo sagrado|orbe|cristal de conjuracao)\b/
      # Livro equipa nas maos (a leitura/foco de 01/09).
      return 'main_hand'  if t =~ /\b(livros?|tomos?|grimorios?|codice|codex|diarios?)\b/
      nil
    end

    por_kind = []
    por_categoria = []
    por_props = []
    por_nome = []
    sem_slot = []

    itens = Item.where.not(kind: %w[material consumable treasure ammunition magic_item])
    itens.find_each do |item|
      props = item.props || {}
      next if props['equip_slot'].present?

      cat = item.category.to_s
      slot, origem =
        case item.kind
        when 'armor'  then ['armor', :kind]
        when 'shield' then ['shield', :kind]
        when 'weapon' then ['main_hand', :kind]
        when 'book'   then ['main_hand', :kind]
        when 'tool'
          cat == 'instrument' ? ['instrument', :categoria] : [nil, nil]
        when 'gear'
          if peca_para_slot.key?(cat)                                  then [peca_para_slot[cat], :categoria]
          elsif cat == 'bag'                                           then ['back', :categoria]
          elsif cat == 'instrument'                                    then ['instrument', :categoria]
          elsif %w[focus holy-symbol].include?(cat)                    then ['main_hand', :categoria]
          elsif %w[vehicle_water vehicle_land tack pack equipment supply].include?(cat) then [nil, nil]
          elsif props['ammunition_types'].present?                     then ['back', :props]
          elsif props['capacity_kg'].to_f.positive?                    then ['back', :props]
          else
            achado = slot_por_nome.call(item.name)
            achado ? [achado, :nome] : [nil, nil]
          end
        else [nil, nil]
        end

      if slot.nil?
        # Ferramenta comum nao se equipa; gear irresoluvel vai ao relatorio.
        sem_slot << item if item.kind == 'gear' && !%w[vehicle_water vehicle_land tack pack equipment supply].include?(cat)
        next
      end

      registro = [item, slot]
      case origem
      when :kind      then por_kind << registro
      when :categoria then por_categoria << registro
      when :props     then por_props << registro
      when :nome      then por_nome << registro
      end

      item.update!(props: props.merge('equip_slot' => slot)) if aplicar
    end

    relatar = lambda do |titulo, lista, com_nome: false|
      puts "== #{titulo} (#{lista.size}) =="
      lista.first(com_nome ? 200 : 8).each do |item, slot|
        puts format('  #%-5d %-36s -> %s', item.id, item.name.to_s[0, 36], slot)
      end
      puts "  … e mais #{lista.size - 8}" if !com_nome && lista.size > 8
      puts
    end

    relatar.call('POR KIND (estrutural)', por_kind)
    relatar.call('POR CATEGORIA (declarada no editor)', por_categoria)
    relatar.call('POR PROPS (recipiente/capacidade)', por_props)
    relatar.call('⚠️ POR NOME — a heuristica congelando; CONFIRA', por_nome, com_nome: true)

    puts "== SEM SLOT — gear sem categoria que nada resolveu (#{sem_slot.size}) =="
    sem_slot.first(40).each { |i| puts format('  #%-5d %-40s', i.id, i.name.to_s[0, 40]) }
    puts "  … e mais #{sem_slot.size - 40}" if sem_slot.size > 40
    puts
    total = por_kind.size + por_categoria.size + por_props.size + por_nome.size
    puts aplicar ? "OK: #{total} item(ns) carimbados." : "Seriam carimbados #{total} (#{por_nome.size} por nome)."
  end
end
