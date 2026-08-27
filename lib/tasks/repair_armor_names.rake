# frozen_string_literal: true

# Alinha os NOMES das armaduras ao PHB pt-BR (que é o que o catálogo do front
# já usa) e repara o estrago que a divergência deixou.
#
#   bin/rails dnd:repair_armor_names            # aplica
#   DRY_RUN=1 bin/rails dnd:repair_armor_names  # só relata
#
# Faz três coisas, nesta ordem — e a ordem IMPORTA:
#
#  1. FUNDE as cascas vazias. `ItemResolver` apontava para slugs em PT que não
#     são a convenção do catálogo, então criava um Item sem `ac_base`/`dex_cap`
#     em vez de achar a armadura real. Quem vestia a casca ficava SEM CA de
#     armadura. A causa foi corrigida em `ARMOR_PT_SLUGS`; isto limpa o passado.
#
#  2. RENOMEIA para o nome do PHB. ⚠️ "Peles" ANTES de "Couro Batido": hoje é o
#     `hide` que se chama "Couro Batido", e é esse nome que o `studded-leather`
#     vai receber. Renomear na ordem errada deixaria dois itens com o mesmo nome.
#
#  3. REPARA as linhas de ficha. `sheet_items.item_name` é DENORMALIZADO — não
#     acompanha o rename. O casamento é por `item_id`, nunca por nome: as 6
#     linhas de `hide` estavam em três grafias ("couro batido", "Couro batido",
#     "Couro Batido") e um match por nome perderia quatro delas.
namespace :dnd do
  desc 'Alinha os nomes das armaduras ao PHB e funde as cascas vazias'
  task repair_armor_names: :environment do
    dry = ENV['DRY_RUN'].present?
    stats = Hash.new(0)
    puts "== repair_armor_names #{'(DRY RUN)' if dry} =="

    # ── 1) cascas vazias → armadura real ───────────────────────────────
    CASCAS = { 'meia-armadura' => 'half-plate', 'cota-de-aneis' => 'ring-mail' }.freeze
    CASCAS.each do |casca_idx, real_idx|
      casca = Item.find_by(api_index: casca_idx)
      real  = Item.find_by(api_index: real_idx)
      next if casca.nil? || real.nil?

      linhas = SheetItem.where(item_id: casca.id)
      puts "  ~ funde casca #{casca_idx} → #{real_idx} (#{linhas.count} ficha(s))"
      unless dry
        linhas.update_all(item_id: real.id, item_index: real.api_index)
        casca.reload.destroy || warn("  ⚠️ casca não saiu: #{casca.errors.full_messages.first}")
      end
      stats[:cascas_fundidas] += 1
    end

    # ── 2) nomes do PHB (ordem: quem LIBERA o nome vem primeiro) ───────
    NOMES = [
      ['hide',            'Peles'],              # libera "Couro Batido"
      ['studded-leather', 'Couro Batido'],
      ['chain-shirt',     'Camisão de Malha'],
      ['scale-mail',      'Brunea'],
      ['half-plate',      'Meia-Armadura'],
      ['ring-mail',       'Cota de Anéis'],
      ['splint',          'Cota de Talas'],
      ['plate',           'Armadura de Placas'],
    ].freeze

    NOMES.each do |idx, nome|
      it = Item.find_by(api_index: idx)
      next puts("  ⚠️ ausente no catálogo: #{idx}") if it.nil?
      next stats[:nomes_ja_ok] += 1 if it.name == nome

      puts "  ~ #{idx}: #{it.name.inspect} → #{nome.inspect}"
      it.update!(name: nome) unless dry
      stats[:nomes_corrigidos] += 1
    end

    # ── 3) linhas de ficha (denormalizadas) ────────────────────────────
    NOMES.each do |idx, nome|
      it = Item.find_by(api_index: idx)
      next if it.nil?
      # Por item_id: pega TODAS as grafias antigas de uma vez.
      linhas = SheetItem.where(item_id: it.id).where.not(item_name: nome)
      n = linhas.count
      next if n.zero?

      puts "  ~ #{n} linha(s) de ficha: → #{nome.inspect} (era #{linhas.distinct.pluck(:item_name).inspect})"
      linhas.update_all(item_name: nome) unless dry
      stats[:linhas_reparadas] += n
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-22s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
