# frozen_string_literal: true

# Reclassifica como CONSUMÍVEL os itens que estavam em `kind: gear` mas se
# gastam ao usar (óleo, veneno, bomba, antídoto).
#
#   bin/rails dnd:reclassify_gear_consumables            # aplica
#   DRY_RUN=1 bin/rails dnd:reclassify_gear_consumables  # só relata
#
# Sintoma: o detalhe do item na bolsa não mostrava "Consumir", porque o gate
# olha o `kind` do catálogo. O jogador via o óleo na mochila e não conseguia
# gastá-lo.
#
# ⚠️ A lista é NOMINAL, não heurística. A regex que os ENCONTROU pega palavra
# solta ("Granada" é a gema, "Cinto de bomba" é o cinto): serve para procurar,
# nunca para decidir. Cada linha abaixo foi olhada uma a uma.
namespace :dnd do
  desc 'Reclassifica óleos/venenos/bombas de `gear` para `consumable`'
  task reclassify_gear_consumables: :environment do
    dry = ENV['DRY_RUN'].present?
    puts "== reclassify_gear_consumables #{'(DRY RUN)' if dry} =="

    # api_index → sub-tipo do consumível.
    ALVOS = {
      # Venenos — gaveta própria; NÃO viram poção (ganhariam "Beber Poção").
      'veneno-basico' => 'poison',
      'veneno-cereja-feerica-de-inverno' => 'poison',
      'veneno-espanta-lobo' => 'poison',
      'veneno-lagrima-de-viuva' => 'poison',
      'veneno-veu-dos-olhos-laspar' => 'poison',
      # Bebidos → poção (é a gaveta que dá o botão "Beber").
      'antidoto' => 'potion',
      'elixir-de-saude' => 'potion',
      # Preparados alquímicos: arremessados ou aplicados.
      'bomba-cola' => 'alchemical',
      'bomba-de-cola' => 'alchemical',
      'bomba-de-fumaca' => 'alchemical',
      'bomba-explosiva' => 'alchemical',
      'frasco-de-bomba' => 'alchemical',
      'oleo-escorregadio' => 'alchemical',
      'oleo-escorradia' => 'alchemical',
      'oleo-flamejante' => 'alchemical',
      'papel-elemental-acido' => 'alchemical',
      # Gastam-se, mas não são alquímicos nem se bebem.
      'bloco-de-incenso' => 'supply',
      'oleo-de-armadura' => 'supply',
      'oleo-para-escreve' => 'supply',
      'oleos-para-cabelos' => 'supply',
    }.freeze

    # Achados pela busca e DELIBERADAMENTE deixados de fora.
    FORA = {
      'cinto-de-bomba' => 'é o CINTO que carrega bombas, não a bomba',
      'racao-animal-1-dia' => 'já tem `category: tack` — alguém a classificou de propósito; ' \
                              'mudar o kind a tiraria da aba de arreios',
    }.freeze

    stats = Hash.new(0)
    ALVOS.each do |idx, subtipo|
      it = Item.find_by(api_index: idx)
      next puts("  ⚠️ ausente no catálogo: #{idx}") && stats[:ausentes] += 1 if it.nil?

      if it.kind == 'consumable' && it.category == subtipo
        stats[:ja_ok] += 1
        next
      end

      fichas = SheetItem.where(item_id: it.id).count
      puts format('  ~ %-34s %-8s → consumable/%-11s (%d ficha(s))',
                  it.name.to_s[0, 34], it.kind, subtipo, fichas)
      it.update!(kind: 'consumable', category: subtipo) unless dry
      stats[:reclassificados] += 1
    end

    puts "\n  ── deixados de FORA de propósito ──"
    FORA.each do |idx, motivo|
      puts "    #{idx}: #{motivo}" if Item.exists?(api_index: idx)
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-20s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
