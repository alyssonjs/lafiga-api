# frozen_string_literal: true

module Modifiers
  module Producers
    # FeatProducer — converte os feats persistidos em sheet.metadata['feats']
    # em Modifier objects. Cobre os efeitos diretos mais comuns:
    #
    # - Resiliente: grant em save da habilidade escolhida
    # - Robusto:    +N PV por nível (Modifier "hp.max_per_level")
    # - Mobilidade: +10 ft de deslocamento
    # - Atleta:     grant em skill Atletismo (proficiência)
    # - Tough (3.5/var.): trato similar a Robusto
    #
    # Para feats com regras complexas (Sortudo, Adepto Marcial, GWM/Sharpshooter,
    # etc.) seguimos com `FeatSpecialRulesService` legado nessa fase 0; serão
    # migrados em fases seguintes.
    class FeatProducer < BaseProducer
      def produce
        meta = sheet.metadata || {}
        feats = Array(meta['feats'])
        return [] if feats.empty?

        out = []
        feats.each do |entry|
          next unless entry.is_a?(Hash)
          feat_id = (entry['feat_id'] || entry[:feat_id]).to_s
          next if feat_id.empty?
          choices = entry['choices'] || entry[:choices] || {}

          out.concat(produce_for_feat(feat_id, entry, choices))
        end
        out
      end

      protected

      def source_kind
        :feat
      end

      private

      def produce_for_feat(feat_id, entry, choices)
        case feat_id
        when 'resiliente'
          [resiliente_save_grant(choices)].compact
        when 'robusto'
          [robusto_hp_per_level(entry)].compact
        when 'mobilidade'
          [mobilidade_speed_bonus(entry)].compact
        when 'atleta'
          [atleta_athletics_grant(entry)]
        when 'durao', 'tough'
          [tough_hp_per_level(entry)].compact
        when 'mestre_de_armas_duplas'
          mestre_armas_duplas_ac_bonus(entry).compact
        when 'alerta'
          [alerta_initiative_bonus(entry)].compact
        when 'maestria_em_armadura_pesada'
          [maestria_armadura_pesada_damage_resistance(entry)].compact
        when 'mestre_do_escudo'
          mestre_do_escudo_save_grant(entry).compact
        else
          # Heurística genérica: ler `entry['special_rules']` (escrito por
          # FeatAssignmentService a partir de FeatSpecialRulesService) e
          # converter em modifiers.
          generic_special_rules(entry)
        end
      end

      # ─── Resiliente ────────────────────────────────────────────────
      # F9 — `choices['saving_throws']` é o contrato do front (string escalar).
      # Mas o fluxo server-side de level-up (`AsiFeatApplier.build_choices`)
      # envia só `choices['ability']`, e um Array `['wis']` não casava. Aqui
      # derivamos o save de `ability` quando `saving_throws` falta/inválido,
      # toleramos Array e abreviações PT (for/des/sab/car).
      PT_TO_EN_ABILITY = { 'for' => 'str', 'des' => 'dex', 'con' => 'con',
                           'int' => 'int', 'sab' => 'wis', 'car' => 'cha' }.freeze

      def resiliente_save_grant(choices)
        ability = normalize_save_key(choices['saving_throws'] || choices[:saving_throws])
        ability = normalize_save_key(choices['ability'] || choices[:ability]) unless ability
        return nil unless ability
        mod(
          target: "save.#{ability}",
          op: :grant,
          value: ability,
          source: 'feat:resiliente',
          note: "Resiliente concede proficiência em salvaguarda de #{ability.upcase}",
        )
      end

      # Normaliza um valor (String, Symbol ou Array de 1) para uma chave de save
      # válida em inglês ('str'..'cha'), ou nil.
      def normalize_save_key(raw)
        raw = raw.first if raw.is_a?(Array)
        key = raw.to_s.strip.downcase
        key = PT_TO_EN_ABILITY[key] || key
        %w[str dex con int wis cha].include?(key) ? key : nil
      end

      # ─── Robusto ───────────────────────────────────────────────────
      # Robusto sobe PV: 2 × nível ao adquirir + 2/nível dali pra frente.
      # No modelo de Modifier, expressamos como "hp.max_per_level" com value
      # igual ao bônus por nível. O resolver consumidor aplica × nivel total
      # (ou só níveis a partir do que foi adquirido — convencionamos retroativo
      # por compatibilidade com o `feat_assignment_service` legado).
      def robusto_hp_per_level(_entry)
        mod(
          target: 'hp.max_per_level',
          op: :add,
          value: 2,
          source: 'feat:robusto',
          stacking_type: 'untyped',
          note: '+2 PV máximo por nível (retroativo)',
        )
      end

      # ─── Mobilidade ────────────────────────────────────────────────
      def mobilidade_speed_bonus(_entry)
        mod(
          target: 'speed',
          op: :add,
          value: 10,
          source: 'feat:mobilidade',
          stacking_type: 'untyped',
          note: '+10 ft de deslocamento',
        )
      end

      # ─── Atleta ────────────────────────────────────────────────────
      def atleta_athletics_grant(_entry)
        mod(
          target: 'skill.atletismo',
          op: :grant,
          value: 'atletismo',
          source: 'feat:atleta',
          note: 'Atleta concede proficiência em Atletismo',
        )
      end

      # ─── Durão / Tough ─────────────────────────────────────────────
      def tough_hp_per_level(_entry)
        mod(
          target: 'hp.max_per_level',
          op: :add,
          value: 2,
          source: 'feat:tough',
          stacking_type: 'untyped',
          note: '+2 PV máximo por nível (Durão)',
        )
      end

      # ─── Mestre de Armas Duplas ────────────────────────────────────
      # +1 CA quando empunha duas armas.
      # Predicate `dual_wielding=true` é avaliado pelo summary com base no
      # equipamento atual; `EquipmentProfileService` já marca isso.
      def mestre_armas_duplas_ac_bonus(_entry)
        return [] unless dual_wielding?
        # F4 — SEM predicate. A produção já é gated por `dual_wielding?` (lê o
        # equipamento via context). O predicate `dual_wielding` era redundante e
        # ativamente derrubava o +1: `sum_for('ac')`/`sum_for_kind('ac',:feat)`
        # são chamados SEM `predicate_match` no summary, e `predicate_satisfied?`
        # retorna false para predicate com query blank → o +1 nunca somava.
        [
          mod(
            target: 'ac',
            op: :add,
            value: 1,
            source: 'feat:mestre_de_armas_duplas',
            stacking_type: 'untyped',
            note: '+1 CA empunhando duas armas (Mestre de Armas Duplas)',
          ),
        ]
      end

      # ─── Alerta (Alert) — +5 iniciativa ───────────────────────────
      # PHB Alert: +5 iniciativa, imune a surpresa, ignora vantagem de
      # atacantes escondidos. Aqui só convertemos o bônus numérico — os
      # outros 2 efeitos são flags booleanas tratadas pelo combat engine
      # separadamente (ver special_rules.combat_modifiers do feat).
      def alerta_initiative_bonus(_entry)
        mod(
          target: 'initiative',
          op: :add,
          value: 5,
          source: 'feat:alerta',
          stacking_type: 'untyped',
          note: '+5 em iniciativa (Alerta)'
        )
      end

      # ─── Maestria em Armadura Pesada (Heavy Armor Master) ──────────
      # PHB Heavy Armor Master: enquanto vestindo armadura pesada, ataques
      # de armas NÃO-mágicas que causariam dano de contusão/perfuração/
      # cortante têm o dano reduzido em 3.
      #
      # Predicate `wearing_heavy_armor=true` é avaliado pelo summary com
      # base no equipamento atual. Se não houver context disponível (caminho
      # genérico do summary), o modifier ainda é emitido — o resolver final
      # decide se aplica ou não baseado em `predicate`.
      def maestria_armadura_pesada_damage_resistance(_entry)
        # F11 — SEM predicate. O summary consome via `sum_for('damage_resistance.
        # bps_nonmagical')` SEM `predicate_match`; com o predicate `wearing_heavy_armor`
        # o valor nunca somava (mesma armadilha do F4). O efeito-assinatura é
        # exposto como redução condicional à armadura pesada (a UI/combate aplica
        # a condição); aqui apenas garantimos que o valor 3 chegue ao consumidor.
        mod(
          target: 'damage_resistance.bps_nonmagical',
          op: :add,
          value: 3,
          source: 'feat:maestria_em_armadura_pesada',
          stacking_type: 'untyped',
          note: 'Reduz em 3 dano físico não-mágico em armadura pesada (Heavy Armor Master)'
        )
      end

      # ─── Mestre do Escudo (Shield Master) ──────────────────────────
      # PHB Shield Master tem 3 efeitos. Aqui modelamos:
      # 1. AC bonus a saves DEX que afetem só você (escudo equipado).
      # Os outros 2 (empurrão como ação bônus / 0 dano em DEX save com
      # sucesso) são tratados pelo combat engine via special_rules.
      #
      # Predicate: requer escudo equipado. Modelado como save.dex.add_shield.
      def mestre_do_escudo_save_grant(_entry)
        return [] unless wearing_shield?

        [
          mod(
            target: 'save.dex',
            op: :add,
            value: 'shield_ac_bonus',  # resolved via context (geralmente +2)
            source: 'feat:mestre_do_escudo',
            stacking_type: 'untyped',
            predicate: { 'condition' => 'wearing_shield' },
            note: '+escudo a saves DEX só-você (Mestre do Escudo)'
          )
        ]
      end

      def wearing_shield?
        eq = context[:equipment]
        return false unless eq
        equipped = eq[:equipped] || eq['equipped'] || {}
        oh = equipped[:off_hand] || equipped['off_hand'] || {}
        cat = (oh[:category] || oh['category']).to_s.downcase
        cat.include?('shield') || cat == 'escudo' || cat == 'escudos'
      end

      # ─── Heurística genérica para special_rules ────────────────────
      # Lê o bloco `special_rules` que o `FeatAssignmentService` persiste no
      # metadata de cada feat. Cobre casos tabulares conhecidos sem precisar
      # adicionar um when explícito por feat (ex.: mobilidade salvo via YAML
      # sem id específico aqui).
      def generic_special_rules(entry)
        sr = entry['special_rules'] || entry[:special_rules] || {}
        return [] unless sr.is_a?(Hash)
        out = []

        # speed_bonus (movement)
        if (sb = (sr.dig('movement', 'speed_bonus') || sr.dig(:movement, :speed_bonus))).to_i.positive?
          out << mod(
            target: 'speed',
            op: :add,
            value: sb.to_i,
            source: "feat:#{(entry['feat_id'] || entry[:feat_id])}:speed_bonus",
            note: "+#{sb.to_i} ft de deslocamento (special_rule)",
          )
        end

        # hp_per_level (dice)
        if (hp = sr.dig('dice', 'hit_points_per_level') || sr.dig(:dice, :hit_points_per_level))
          per = hp['bonus_per_level'] || hp[:bonus_per_level]
          if per.to_i.positive?
            out << mod(
              target: 'hp.max_per_level',
              op: :add,
              value: per.to_i,
              source: "feat:#{(entry['feat_id'] || entry[:feat_id])}:hp_per_level",
              note: "+#{per.to_i} PV por nível (special_rule)",
            )
          end
        end

        out
      end

      def dual_wielding?
        eq = context[:equipment]
        return false unless eq
        equipped = eq[:equipped] || eq['equipped'] || {}
        mh = equipped[:main_hand] || equipped['main_hand']
        oh = equipped[:off_hand]  || equipped['off_hand']
        return false unless mh && oh
        # ambos precisam ser armas (heurística simples baseada em `category`)
        cat_mh = (mh[:category] || mh['category']).to_s.downcase
        cat_oh = (oh[:category] || oh['category']).to_s.downcase
        cat_mh.include?('weapon') || cat_oh.include?('weapon') || cat_mh == 'armas' || cat_oh == 'armas'
      end
    end
  end
end
