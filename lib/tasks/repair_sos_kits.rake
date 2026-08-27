# frozen_string_literal: true

# Junta as 6 entradas homebrew de "Kit SOS" no Kit de Primeiros Socorros do
# catálogo e tira a contagem do NOME, pondo-a no contador de usos.
#
#   bin/rails dnd:repair_sos_kits            # aplica
#   DRY_RUN=1 bin/rails dnd:repair_sos_kits  # só relata
#
# A mesa vinha codificando os usos restantes no nome do item — "Kit SOS x3",
# "x9", "x10" — porque o kit homebrew não tinha contador. Seis entradas de
# catálogo para o mesmo kit, e o `seed_item_uses` reclamava a cada deploy.
#
# ⚠️ Por que `xN` é USO e não QUANTIDADE, que era a dúvida que travava isto:
# TODAS as 7 linhas de ficha têm `quantity: 1`. Se `x3` fossem três kits, a
# quantidade seria 3 — o número está no nome justamente porque não havia onde
# guardá-lo. E o kit do PHB tem `uses_max: 10`, que é exatamente o "x10".
#
# ⚠️ "Kit SOS 7pl" fica de FORA: o "pl" não é vocabulário conhecido (7 usos?
# 7 poções? outra coisa?) e adivinhar mudaria a ficha de um jogador. Relatado
# para o mestre decidir.
namespace :dnd do
  desc 'Junta os "Kit SOS xN" no Kit de Primeiros Socorros, com usos reais'
  task repair_sos_kits: :environment do
    dry = ENV['DRY_RUN'].present?
    puts "== repair_sos_kits #{'(DRY RUN)' if dry} =="

    canon = Item.find_by(api_index: 'kit-de-primeiros-socorros')
    if canon.nil?
      puts '  ⚠️ Kit de Primeiros Socorros ausente do catálogo — rode `dnd:seed_item_uses` antes.'
      next
    end
    teto = canon.props['uses_max'].to_i
    puts "  canônico: #{canon.name} (uses_max=#{teto})\n\n"

    # api_index homebrew → usos restantes lidos do nome. `nil` = sem número,
    # entra CHEIO (chave ausente = cheio, o contrato do cano de usos).
    ALVOS = {
      'kit-sos' => nil,
      'kit-sos-x3' => 3,
      'kit-sos-x9' => 9,
      'kit-sos-x10' => 10,
      'kit-de-sos-x10' => 10,
    }.freeze
    FORA = { 'kit-sos-7pl' => '"7pl" não é vocabulário conhecido — 7 usos? 7 poções? Só o mestre sabe.' }.freeze

    stats = Hash.new(0)
    ALVOS.each do |idx, usos|
      it = Item.find_by(api_index: idx)
      next if it.nil?

      SheetItem.where(item_id: it.id).each do |si|
        restante = usos && usos < teto ? usos : nil
        puts format('  ~ ficha %-4s %-18s → %s%s', si.sheet_id, si.item_name.to_s[0, 18],
                    canon.name, restante ? " (#{restante}/#{teto} usos)" : " (cheio, #{teto})")
        unless dry
          props = (si.props_json || {}).dup
          # Sem número no nome, a chave fica AUSENTE = cheio. Escrever o teto
          # seria equivalente, mas a ausência é o estado canônico do cano.
          restante ? props['uses_remaining'] = restante : props.delete('uses_remaining')
          si.update!(item_id: canon.id, item_index: canon.api_index,
                     item_name: canon.name, props_json: props)
        end
        stats[:linhas_migradas] += 1
      end

      # A entrada homebrew fica órfã — sai. `restrict_with_error` barra a que
      # estiver em receita.
      unless dry
        if SheetItem.where(item_id: it.id).exists?
          stats[:entradas_mantidas_em_uso] += 1
        elsif it.destroy
          stats[:entradas_removidas] += 1
        else
          puts "    ⚠️ não saiu: #{it.name} (#{it.errors.full_messages.first})"
          stats[:entradas_mantidas_em_uso] += 1
        end
      else
        stats[:entradas_a_remover] += 1
      end
    end

    puts "\n  ── deixado de FORA ──"
    FORA.each do |idx, motivo|
      it = Item.find_by(api_index: idx)
      next unless it
      n = SheetItem.where(item_id: it.id).count
      puts "    #{it.name} (#{n} ficha(s)): #{motivo}"
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-26s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
