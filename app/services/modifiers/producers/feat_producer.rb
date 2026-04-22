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
        else
          # Heurística genérica: ler `entry['special_rules']` (escrito por
          # FeatAssignmentService a partir de FeatSpecialRulesService) e
          # converter em modifiers.
          generic_special_rules(entry)
        end
      end

      # ─── Resiliente ────────────────────────────────────────────────
      def resiliente_save_grant(choices)
        ability = (choices['saving_throws'] || choices[:saving_throws]).to_s.downcase
        return nil if ability.empty?
        return nil unless %w[str dex con int wis cha].include?(ability)
        mod(
          target: "save.#{ability}",
          op: :grant,
          value: ability,
          source: 'feat:resiliente',
          note: "Resiliente concede proficiência em salvaguarda de #{ability.upcase}",
        )
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
        [
          mod(
            target: 'ac',
            op: :add,
            value: 1,
            source: 'feat:mestre_de_armas_duplas',
            stacking_type: 'untyped',
            predicate: { 'condition' => 'dual_wielding' },
            note: '+1 CA empunhando duas armas (Mestre de Armas Duplas)',
          ),
        ]
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
