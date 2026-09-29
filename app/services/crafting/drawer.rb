# frozen_string_literal: true

module Crafting
  # A gaveta da BOLSA em que o item criado cai — espelho de
  # `bagCategoryFromCatalog` (front, `bagConstants.ts`). A categoria GRAVADA
  # vence a do catálogo na bolsa, então gravar a gaveta certa aqui é o que põe a
  # poção em "Poções" e não em "Itens Gerais".
  #
  # O front não tem gaveta para item mágico (`magic_item` → nulo); aqui ele vai
  # pela peça-base, que é onde o jogador o procura.
  module Drawer
    VEICULOS = %w[vehicle_land vehicle_water tack].freeze
    VESTUARIO = %w[ring earrings necklace choker amulet circlet helmet mask goggles
                   bracelet_left bracelet_right belt belt_leg gloves gauntlets boots
                   anklet cloak brooch locket].freeze

    module_function

    def for(item)
      k = item.kind.to_s.strip.downcase
      c = item.category.to_s.strip.downcase
      return 'Kits' if k == 'pack' || c == 'pack'

      case k
      when 'material' then 'Matérias-Primas'
      when 'treasure' then 'Obras de Arte'
      when 'weapon', 'ammunition' then 'Armas'
      when 'armor', 'shield' then 'Armaduras'
      when 'consumable' then consumivel(c)
      when 'tool' then c == 'kit' ? 'Kits' : 'Itens Gerais'
      when 'gear'
        return 'Equipamentos' if VEICULOS.include?(c)
        return 'Vestuário' if VESTUARIO.include?(c)

        'Itens Gerais'
      when 'magic_item'
        return 'Armas' if c == 'weapon'
        return 'Armaduras' if %w[armor shield].include?(c)
        return 'Vestuário' if VESTUARIO.include?(c)

        consumivel(c)
      else 'Itens Gerais'
      end
    end

    def consumivel(c)
      return 'Poções' if c == 'potion'
      return 'Pergaminhos' if c == 'scroll'

      'Itens Gerais'
    end
  end
end
