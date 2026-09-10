# frozen_string_literal: true

# O que está EQUIPADO não está guardado numa bolsa.
#
#   DRY_RUN=1 bundle exec rake dnd:fix_equipped_still_in_bag
#
# ⚠️ A linha equipada mantinha `props_json['bag_sheet_item_id']`, e a tela
# listava o item DENTRO da mochila e na mão ao mesmo tempo. O peso contava
# certo; quem mentia era a bolsa.
#
# O caminho de equipar já limpa o ponteiro a partir de 11/09 — este rake alcança
# o que ficou gravado antes.
namespace :dnd do
  desc 'Limpa o ponteiro de bolsa das linhas EQUIPADAS (DRY_RUN=1 relata)'
  task fix_equipped_still_in_bag: :environment do
    seco = ENV['DRY_RUN'].present?
    chave = SheetItem::BAG_CONTAINER_PROP
    alvos = SheetItem.where(equipped: true).select { |si| (si.props_json || {})[chave].present? }

    alvos.each do |si|
      puts format('  ficha %-5s %-28s slot=%s', si.sheet_id, si.item_name.to_s[0, 26], si.slot)
      next if seco

      # ⚠️ `update_column`: nada mais nesta linha deve mudar, e as validações de
      # equipagem (proficiência, conflitos) não têm de correr para tirar um
      # ponteiro que já não vale.
      si.update_column(:props_json, (si.props_json || {}).except(chave))
    end

    puts "dnd:fix_equipped_still_in_bag: #{alvos.size} linha(s)#{seco ? ' [DRY_RUN]' : ''}."
  end
end
