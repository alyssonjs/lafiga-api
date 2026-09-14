# frozen_string_literal: true

# Descrições CORTADAS em 120 caracteres nas linhas da ficha (14/09/2026).
#
# O "+ Novo Item" copiava a descrição do catálogo para `props_json` cortada em
# 120 caracteres: o corte servia ao seletor, mas era a cópia que a linha
# gravava. A erva Covette da mesa terminava em "semelhante à da co". O front já
# grava o texto inteiro; esta rake conserta as linhas antigas (8 em produção).
#
#   bin/rails dnd:repair_truncated_item_descriptions           # só relata (DRY RUN)
#   APPLY=1 bin/rails dnd:repair_truncated_item_descriptions   # grava
#
# ⚠️ Só troca quando a cópia tem EXATAMENTE 120 caracteres e é o COMEÇO do
# texto do catálogo — descrição escrita à mão não casa com isso e fica como está.
#
# ⚠️ `update_column`: é conserto de TEXTO. `update!` rodaria a validação de
# proficiência e a exclusividade de slot, e um item equipado por quem não tem
# proficiência travaria o conserto de uma linha que só precisa do texto.
namespace :dnd do
  CORTE_DESCRICAO_NA_BOLSA = 120

  desc 'Repõe o texto do catálogo nas descrições da bolsa cortadas em 120 caracteres (APPLY=1 grava)'
  task repair_truncated_item_descriptions: :environment do
    aplicar = ENV['APPLY'] == '1'
    puts "== repair_truncated_item_descriptions #{aplicar ? '(APLICANDO)' : '(DRY RUN — use APPLY=1 para gravar)'} =="
    reparadas = 0

    SheetItem.includes(:item).where.not(item_id: nil).find_each do |si|
      copia = (si.props_json || {})['description']
      next unless copia.is_a?(String) && copia.length == CORTE_DESCRICAO_NA_BOLSA

      inteira = si.item&.description.to_s
      next unless inteira.length > copia.length && inteira.start_with?(copia)

      puts format('  ~ ficha %-5s %-28s %d → %d caracteres',
                  si.sheet_id, si.item_name.to_s[0, 28], copia.length, inteira.length)
      reparadas += 1
      si.update_column(:props_json, si.props_json.merge('description' => inteira)) if aplicar
    end

    puts "\n== resultado ==\n  reparadas #{reparadas}"
    puts "\n(DRY RUN — nada foi gravado)" unless aplicar
  end
end
