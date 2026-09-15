# frozen_string_literal: true

# Subcategorias do "Equipamento de aventura" (14/09/2026).
#
# A aba Equipamentos juntava os itens do livro numa gaveta só (`category:
# equipment`): Algibeira, Aljava, focos, lanternas, cordas e roupas lado a lado,
# e o "Criar item" não tinha como saber o que o mestre estava criando. O mestre
# escolheu subcategorias (regra + organização) e que os itens do livro fossem
# classificados por `api_index` — nunca por nome solto.
#
#   bin/rails dnd:classify_adventuring_gear           # só relata (DRY RUN)
#   APPLY=1 bin/rails dnd:classify_adventuring_gear   # grava
#
# ⚠️ A categoria só ORGANIZA. A regra continua na prop declarada:
# `coin_capacity` (Algibeira), `equipment_slot: quiver` (aljava), `arcane_focus`
# ou o nome (foco). As três categorias de foco são as que o front JÁ reconhece.
#
# ⚠️ Não passa por cima do mestre: só reclassifica quem ainda está numa categoria
# genérica (nula, `equipment`, `gear`, `focus`) ou foi CORROMPIDO pelo editor de
# transporte (`vehicle_land`/`vehicle_water`/`tack` num item que não é veículo —
# a "Roupa de viajante" de produção virou veículo terrestre assim).
#
# ⚠️ Constantes com nome próprio: as de rake vivem no escopo global.
namespace :dnd do
  CLASSIFICACAO_AVENTURA = {
    'coin-pouch' => %w[algibeira],
    'ammo-container' => %w[aljava porta-virotes bolsa-de-municao],
    'arcane-focus' => %w[foco-arcano bastao-foco-arcano cajado-foco-arcano cristal-foco-arcano
                         orbe-foco-arcano varinha-foco-arcano],
    'druidic-focus' => %w[foco-druidico cajado-de-madeira-foco-druidico ramo-de-visco-foco-druidico
                          totem-foco-druidico varinha-de-teixo-foco-druidico],
    'holy-symbol' => %w[amuleto-simbolo-sagrado emblema-simbolo-sagrado relicario-simbolo-sagrado],
    # PHB cap. 5, tabela de capacidade de recipientes. Só organiza: guardar itens
    # dentro continua sendo coisa da aba Bolsas.
    'container' => %w[mochila barril bau balde cesto saco frasco garrafa-de-vidro jarra caneca
                      panela-de-ferro porta-mapas-ou-pergaminhos],
    'lighting' => %w[lampada lanterna-coberta lanterna-furta-fogo caixa-de-fogo parafina],
    'exploration' => %w[algemas armadilha-de-caca arpeu ariete-portatil corda-15m corda-de-seda-15-metros
                        corrente-3-metros escada-3-metros estrepes-bolsa-com-20 fechadura kit-de-escalada
                        marreta martelo pa pe-de-cabra picareta-de-minerador pitons pregos-de-ferro-10
                        roldana-e-polia saco-com-esferas vara-3-metros tenda-para-duas-pessoas
                        saco-de-dormir cobertor-de-inverno equipamento-de-pescaria apito-de-advertencia
                        sino luneta lente-de-aumento espelho-de-aco],
    'writing' => %w[caneta-tinteiro tinta-frasco-de-30ml papel-uma-folha pergaminho-uma-folha giz-1-peca sinete],
    # Roupa de corpo fica em Equipamentos (subcategoria Roupas): o Vestuário
    # exige slot em toda peça (29/08) e a ficha não tem slot de roupa.
    'clothes' => %w[robes roupas-comuns roupas-de-entretenimento roupas-finas roupa-de-viajante],
    # O manto tem slot de manto: esse sim é peça de Vestuário.
    'cloak' => %w[manto],
  }.freeze

  CATEGORIAS_SOBRESCREVIVEIS_AVENTURA = [nil, 'equipment', 'gear', 'focus',
                                         'vehicle_land', 'vehicle_water', 'tack'].freeze

  desc 'Classifica o equipamento de aventura do livro nas subcategorias (APPLY=1 grava)'
  task classify_adventuring_gear: :environment do
    aplicar = ENV['APPLY'] == '1'
    puts "== classify_adventuring_gear #{aplicar ? '(APLICANDO)' : '(DRY RUN — use APPLY=1 para gravar)'} =="
    stats = Hash.new(0)

    CLASSIFICACAO_AVENTURA.each do |categoria, indices|
      indices.each do |idx|
        item = Item.find_by(api_index: idx)
        if item.nil?
          stats[:ausentes] += 1
          next
        end

        if item.category == categoria
          stats[:ja_ok] += 1
          next
        end

        unless item.kind == 'gear' && CATEGORIAS_SOBRESCREVIVEIS_AVENTURA.include?(item.category)
          puts format('  = mantido %-34s %s/%s (categoria escolhida pelo mestre)',
                      item.name.to_s[0, 34], item.kind, item.category.inspect)
          stats[:mantidos] += 1
          next
        end

        props = (item.props || {}).dup
        props['wardrobe_piece'] ||= categoria if categoria == 'cloak'
        props['equip_slot'] ||= 'cloak' if categoria == 'cloak'

        fichas = SheetItem.where(item_id: item.id).count
        puts format('  ~ %-36s %-16s → %s (%d ficha(s))',
                    item.name.to_s[0, 36], item.category.inspect, categoria, fichas)
        item.update!(category: categoria, props: props) if aplicar
        stats[:classificados] += 1
      end
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-14s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" unless aplicar
  end
end
