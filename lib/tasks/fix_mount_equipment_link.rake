# frozen_string_literal: true

require 'json'

# Equipamento de MONTARIA sem vínculo com a linha da ficha.
#
#   DRY_RUN=1 bundle exec rake dnd:fix_mount_equipment_link
#
# ⚠️ O alforje equipado na montaria continuava na bolsa do dono: pesava, aparecia
# em "Soltos", e o mesmo objeto podia ir para duas montarias.
#
# A causa é LEGADO, não código vivo: o vínculo é o `sheetItemId` gravado no
# `equipment` do companion, e as entradas escritas antes de ele existir só têm o
# slug do catálogo (`itemIndex`). Sem o id, `mountEquippedItemIds` devolve vazio,
# `stowOnMount` nunca é chamado e o item nunca sai da bolsa. Vale para os QUATRO
# slots — sela, barda, alforje e freio.
#
# O caminho novo já grava o id (`mountEquippablesFrom` → `withMountSlot`), então
# isto é uma passada única sobre o que ficou para trás.
namespace :dnd do
  desc 'Liga o equipamento de montaria à linha da ficha e tira-o da bolsa (DRY_RUN=1 relata)'
  task fix_mount_equipment_link: :environment do
    seco = ENV['DRY_RUN'].present?
    slots = %w[saddle barding bags harness]
    ligados = 0
    sem_par = []
    reservadas = []

    Sheet.find_each do |sheet|
      comps = sheet.companions
      comps = (JSON.parse(comps) rescue []) if comps.is_a?(String)
      next unless comps.is_a?(Array) && comps.any?

      mudou = false
      novos = comps.map do |c|
        next c unless c.is_a?(Hash)

        eq = c['equipment']
        next c unless eq.is_a?(Hash)

        eq2 = eq.dup
        slots.each do |slot|
          entrada = eq2[slot]
          next unless entrada.is_a?(Hash) && entrada['sheetItemId'].blank?

          slug = entrada['itemIndex'].to_s
          nome = entrada['name'].to_s

          # ⚠️ Casa por `item_index` primeiro (é o que o `itemIndex` guarda) e
          # cai no NOME só depois — a mesma leitura índice-primeiro do resto do
          # modelo. E só considera linha LIVRE: uma já presa noutra montaria ou
          # equipada no dono não pode ser reivindicada aqui.
          candidatas = SheetItem.where(sheet_id: sheet.id).select do |si|
            livre = !si.equipped && (si.props_json || {})[SheetItem::MOUNT_CONTAINER_PROP].blank?
            livre && (si.item_index.to_s == slug || si.item_name.to_s.casecmp?(nome))
          end
          # ⚠️ Em DRY_RUN nada é gravado, então sem esta reserva em memória a
          # MESMA linha apareceria como resposta para duas montarias — foi o que
          # o primeiro relatório mostrou, e daria a impressão de haver dois
          # alforjes onde há um.
          alvo = candidatas.find { |si| !reservadas.include?(si.id) }
          reservadas << alvo.id if alvo

          if alvo.nil?
            sem_par << "ficha #{sheet.id} · #{c['name']} · #{slot} · #{nome.inspect}"
            next
          end

          puts format('  ficha %-4s %-16s %-8s %-20s -> linha %s', sheet.id, c['name'].to_s[0, 14], slot, nome[0, 18], alvo.id)
          ligados += 1
          next if seco

          eq2[slot] = entrada.merge('sheetItemId' => alvo.id.to_s)
          alvo.update_column(
            :props_json,
            (alvo.props_json || {}).merge(SheetItem::MOUNT_CONTAINER_PROP => c['id'])
          )
          mudou = true
        end
        eq2.equal?(eq) ? c : c.merge('equipment' => eq2)
      end

      sheet.update_column(:companions, novos) if mudou && !seco
    end

    puts "dnd:fix_mount_equipment_link: #{ligados} entrada(s) ligada(s)#{seco ? ' [DRY_RUN]' : ''}."
    if sem_par.any?
      puts "⚠️ #{sem_par.size} sem linha correspondente na ficha (o item já não existe, ou já está preso noutro sítio):"
      sem_par.first(8).each { |s| puts "     #{s}" }
    end
  end
end
