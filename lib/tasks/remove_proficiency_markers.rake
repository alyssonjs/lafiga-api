# frozen_string_literal: true

namespace :dnd do
  desc 'Remove do catalogo de ITENS os marcadores de proficiencia (idempotente)'
  # "Veiculos (terrestres)" e "Veiculos (aquaticos)" nao sao itens: sao
  # PROFICIENCIAS. Entraram no catalogo pelo `dnd:seed_phb_tools` e apareciam na
  # aba de ferramentas, ao lado de kits e utensilios que o jogador de facto
  # compra.
  #
  # O vocabulario da proficiencia NAO depende deles: vive em
  # `config/backgrounds_phb.yml` (texto) e em `toolsCatalog.ts` (lista estatica).
  MARCADORES = %w[veiculos-terrestres veiculos-aquaticos].freeze

  task remove_proficiency_markers: :environment do
    removidos = []
    em_uso = []
    ausentes = 0

    MARCADORES.each do |idx|
      item = Item.find_by(api_index: idx)
      if item.nil?
        ausentes += 1
        next
      end

      # Guarda: se alguem tem o item numa ficha, NAO apaga em silencio — apagar
      # o catalogo deixaria a linha da ficha orfa sem aviso.
      usos = SheetItem.where(item_id: item.id).count
      if usos.positive?
        em_uso << "#{idx} (#{usos} ficha#{'s' if usos > 1})"
        next
      end

      item.destroy!
      removidos << idx
    end

    puts "[dnd:remove_proficiency_markers] removidos=#{removidos.size} ja_ausentes=#{ausentes} em_uso=#{em_uso.size}"
    puts "  removidos: #{removidos.join(', ')}" if removidos.any?
    em_uso.each { |m| puts "  MANTIDO (em uso): #{m}" }
  end
end
