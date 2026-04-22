# frozen_string_literal: true

module Modifiers
  module Producers
    # EquippedItemProducer — converte itens mágicos equipados em Modifier objects.
    # Utiliza `MagicItemRules` como fonte de verdade dos efeitos (aplicando
    # typed stacking interno), e re-emite na forma canônica do pipeline.
    #
    # Targets cobertos (Fase 2):
    # - "weapon.attack" / "weapon.damage" (com predicate "weapon.slot")
    # - "ac"
    # - "speed"
    # - "ability.<str|dex|con|int|wis|cha>" (op :add e :set)
    # - "resistance.<damage_type>"           (op :grant)
    # - "damage_immunity.<damage_type>"      (op :grant)
    # - "damage_vulnerability.<type>"        (op :grant)
    # - "condition_immunity.<condition>"     (op :grant)
    # - "advantage.save.<ability>"           (op :grant)
    # - "advantage.skill.<skill>"            (op :grant)
    # - "passive_feature"                    (op :grant, value: { name, desc, source })
    class EquippedItemProducer < BaseProducer
      def produce
        equipment = context[:equipment] || EquipmentProfileService.new(sheet).call
        mi = MagicItemRules.new(sheet, equipment: equipment).call
        out = []

        out.concat(weapon_modifiers(mi))
        out.concat(ac_modifiers(mi))
        out.concat(speed_modifiers(mi))
        out.concat(ability_modifiers(mi))
        out.concat(resistance_modifiers(mi))
        out.concat(advantage_modifiers(mi))
        out.concat(passive_feature_modifiers(mi))

        out
      rescue => e
        Rails.logger.warn("EquippedItemProducer: erro ao computar mods para sheet ##{sheet.id}: #{e.class}: #{e.message}")
        []
      end

      protected

      def source_kind
        :item
      end

      private

      def weapon_modifiers(mi)
        out = []
        wm = mi[:weapon_mods] || {}
        %i[main_hand off_hand].each do |slot|
          hand = wm[slot] || {}
          atk = hand[:attack].to_i
          dmg = hand[:damage].to_i
          if atk != 0
            out << mod(
              target: 'weapon.attack', op: :add, value: atk,
              source: "item:magic:#{slot}", stacking_type: 'magico',
              predicate: { 'weapon.slot' => slot.to_s },
              note: "Item mágico em #{slot} (+#{atk} ataque)",
            )
          end
          if dmg != 0
            out << mod(
              target: 'weapon.damage', op: :add, value: dmg,
              source: "item:magic:#{slot}", stacking_type: 'magico',
              predicate: { 'weapon.slot' => slot.to_s },
              note: "Item mágico em #{slot} (+#{dmg} dano)",
            )
          end
        end
        out
      end

      def ac_modifiers(mi)
        ac = mi[:ac_bonus].to_i
        return [] if ac == 0
        [mod(
          target: 'ac', op: :add, value: ac,
          source: 'item:magic:armor_or_shield',
          stacking_type: 'magico',
          note: 'Bônus de CA agregado de itens mágicos',
        )]
      end

      def speed_modifiers(mi)
        sp = mi[:speed_bonus].to_i
        return [] if sp == 0
        [mod(
          target: 'speed', op: :add, value: sp,
          source: 'item:magic:speed',
          stacking_type: 'magico',
          note: "+#{sp} ft de deslocamento (item mágico)",
        )]
      end

      def ability_modifiers(mi)
        out = []
        (mi[:ability_bonuses] || {}).each do |ab, val|
          next if val.to_i == 0
          out << mod(
            target: "ability.#{ab}", op: :add, value: val.to_i,
            source: "item:magic:ability_bonus:#{ab}",
            stacking_type: 'magico',
            note: "Item mágico: +#{val} #{ab.upcase}",
          )
        end
        (mi[:ability_sets] || {}).each do |ab, val|
          next if val.to_i <= 0
          out << mod(
            target: "ability.#{ab}", op: :set, value: val.to_i,
            source: "item:magic:ability_set:#{ab}",
            note: "Item mágico fixa #{ab.upcase} em #{val} (se maior que o valor atual)",
          )
        end
        out
      end

      def resistance_modifiers(mi)
        out = []
        Array(mi[:resistances]).each do |t|
          out << mod(
            target: "resistance.#{t}", op: :grant, value: t,
            source: "item:magic:resistance:#{t}",
            note: "Resistência a dano de #{t}",
          )
        end
        Array(mi[:damage_immunities]).each do |t|
          out << mod(
            target: "damage_immunity.#{t}", op: :grant, value: t,
            source: "item:magic:immunity:#{t}",
            note: "Imunidade a dano de #{t}",
          )
        end
        Array(mi[:damage_vulnerabilities]).each do |t|
          out << mod(
            target: "damage_vulnerability.#{t}", op: :grant, value: t,
            source: "item:magic:vulnerability:#{t}",
            note: "Vulnerabilidade a dano de #{t}",
          )
        end
        Array(mi[:condition_immunities]).each do |c|
          out << mod(
            target: "condition_immunity.#{c}", op: :grant, value: c,
            source: "item:magic:condition_immunity:#{c}",
            note: "Imune à condição #{c}",
          )
        end
        out
      end

      def advantage_modifiers(mi)
        out = []
        Array(mi[:save_advantages]).each do |ab|
          out << mod(
            target: "advantage.save.#{ab}", op: :grant, value: ab,
            source: "item:magic:advantage_save:#{ab}",
            note: "Vantagem em testes de salvaguarda de #{ab.upcase}",
          )
        end
        Array(mi[:skill_advantages]).each do |sk|
          out << mod(
            target: "advantage.skill.#{sk}", op: :grant, value: sk,
            source: "item:magic:advantage_skill:#{sk}",
            note: "Vantagem em testes de #{sk}",
          )
        end
        out
      end

      def passive_feature_modifiers(mi)
        Array(mi[:passive_features]).map do |feat|
          mod(
            target: 'passive_feature', op: :grant,
            value: { name: feat[:name], desc: feat[:desc], source: feat[:source] },
            source: "item:magic:passive:#{feat[:source]}",
            note: feat[:name],
          )
        end
      end
    end
  end
end
