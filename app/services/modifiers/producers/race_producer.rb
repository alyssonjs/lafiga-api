# frozen_string_literal: true

module Modifiers
  module Producers
    # RaceProducer — gera Modifiers a partir da raça/sub-raça do personagem,
    # lendo os `grants` dos trait_definitions do `config/race_rules.yml`
    # (fonte canônica, via `RaceRules.apply` + `RaceRules.trait_definitions`).
    #
    # Motivação (R2 da varredura de raças): até aqui NENHUM producer cobria
    # raça — o slot `race:` estava comentado no ModifierResolver. Resultado:
    # resistências/imunidades/vantagens raciais (Resiliência Anã → veneno,
    # ancestralidade do Draconato → elemento, legados Tiefling, Ancestralidade
    # Feérica, Bravura, Astúcia Gnômica) só sobreviviam como TEXTO em
    # `traits[].description`, nunca em `modifiers.resistances/condition_immunities/
    # save_advantages`. O front precisava parsear texto.
    #
    # Canal IDÊNTICO ao SubklassProducer/EquippedItemProducer:
    #   - `resistance.<tipo>`        op :grant  → modifiers.resistances
    #   - `damage_immunity.<tipo>`   op :grant  → modifiers.damage_immunities
    #   - `condition_immunity.<cond>` op :grant → modifiers.condition_immunities
    #   - `advantage.save`           op :grant  → modifiers.save_advantages
    #   - `advantage.skill`          op :grant  → modifiers.skill_advantages
    #
    # Shapes lidos do trait_def (`grants:`), todos OPCIONAIS:
    #   grants:
    #     defenses:
    #       resistance: [veneno]                 # resistência a dano
    #       immunity:   [...]                    # imunidade a dano
    #       conditions_immunity: ["Sono mágico"] # imunidade a condição
    #     advantages:
    #       saves:  [Veneno, Enfeitiçado]        # vantagem em testes de resistência
    #       skills: [...]                        # vantagem em perícia
    #
    # Interpolação `<campo>`: um valor como "<damage>" é resolvido a partir do
    # CAMPO do trait ref na sub-raça (ex.: a sub-raça do Draconato declara
    # `{ key: damage_resistance_from_ancestry, damage: "Veneno" }`). Assim um
    # único trait_def serve as 10 ancestralidades sem repetir o tipo de dano.
    #
    # Convenções:
    # - `source_kind: :race` — para a UI separar a origem.
    # - `stacking_type` default ('untyped').
    # - Producer PURO: não persiste, não muta a sheet; devolve [] em erro.
    class RaceProducer < BaseProducer
      def produce
        return [] if sheet.race_id.blank?

        applied = resolve_applied
        return [] unless applied.is_a?(Hash)

        trait_defs = RaceRules.trait_definitions
        out = []
        Array(applied[:traits]).each do |trait_ref|
          ref = normalize_ref(trait_ref)
          key = ref[:key]
          next if key.blank?

          trait_def = trait_defs[key.to_sym] || trait_defs[key.to_s]
          next unless trait_def.is_a?(Hash)

          grants = trait_def[:grants] || trait_def['grants']
          next unless grants.is_a?(Hash)

          out.concat(defenses_grants(key, ref, grants))
          out.concat(advantage_grants(key, ref, grants))
        end
        out
      rescue StandardError => e
        Rails.logger.warn("RaceProducer: falhou para sheet ##{sheet&.id}: #{e.class}: #{e.message}")
        []
      end

      protected

      def source_kind
        :race
      end

      private

      # Resolve a regra racial canônica (mesma taxonomia que RaceProfileService:
      # api_index → normalize_race_key / canonical_subrace_key). Não depende do
      # race_summary persistido — lê o YAML, então funciona mesmo em fichas cujo
      # snapshot é antigo.
      def resolve_applied
        raw_race = sheet.race&.api_index.presence || sheet.race&.name&.parameterize&.underscore
        raw_sub  = sheet.sub_race&.api_index.presence || sheet.sub_race&.name&.parameterize&.underscore
        race = RaceRules.normalize_race_key(raw_race)
        sub  = RaceRules.canonical_subrace_key(race, raw_sub)
        RaceRules.apply(race_id: race, subrace_id: sub, choices: {})
      rescue StandardError
        nil
      end

      def normalize_ref(trait_ref)
        if trait_ref.is_a?(Hash)
          trait_ref.symbolize_keys
        else
          { key: trait_ref.to_s }
        end
      end

      def defenses_grants(key, ref, grants)
        defenses = grants[:defenses] || grants['defenses']
        return [] unless defenses.is_a?(Hash)

        out = []
        damage_values(defenses[:resistance] || defenses['resistance'], ref).each do |t|
          out << mod(target: "resistance.#{t}", op: :grant, value: t,
                     source: defense_source(key, 'resistance', t),
                     note: "Resistência a dano de #{t}")
        end
        damage_values(defenses[:immunity] || defenses['immunity'], ref).each do |t|
          out << mod(target: "damage_immunity.#{t}", op: :grant, value: t,
                     source: defense_source(key, 'damage_immunity', t),
                     note: "Imunidade a dano de #{t}")
        end
        cond_raw = defenses[:conditions_immunity] || defenses['conditions_immunity'] ||
                   defenses[:condition_immunity] || defenses['condition_immunity']
        damage_values(cond_raw, ref).each do |c|
          out << mod(target: "condition_immunity.#{c}", op: :grant, value: c,
                     source: defense_source(key, 'condition_immunity', c),
                     note: "Imune à condição #{c}")
        end
        out
      end

      def advantage_grants(key, ref, grants)
        advantages = grants[:advantages] || grants['advantages']
        return [] unless advantages.is_a?(Hash)

        out = []
        damage_values(advantages[:saves] || advantages['saves'], ref).each do |label|
          out << mod(target: 'advantage.save', op: :grant, value: label,
                     source: defense_source(key, 'advantage_save', label),
                     note: "Vantagem em testes de resistência vs #{label}")
        end
        damage_values(advantages[:skills] || advantages['skills'], ref).each do |label|
          out << mod(target: 'advantage.skill', op: :grant, value: label,
                     source: defense_source(key, 'advantage_skill', label),
                     note: "Vantagem em #{label}")
        end
        out
      end

      # Normaliza um valor (Array/String), interpolando placeholders `<campo>`
      # a partir do trait ref (ex.: "<damage>" → ref[:damage]).
      def damage_values(raw, ref)
        Array(raw).map { |t| interpolate(t, ref) }.map { |t| t.to_s.strip }.reject(&:empty?)
      end

      def interpolate(value, ref)
        value.to_s.gsub(/<([^<>\s]+)>/) do
          field = Regexp.last_match(1)
          (ref[field.to_sym] || ref[field]).to_s
        end
      end

      def defense_source(key, kind, value)
        ["race", key, kind, value.to_s.parameterize].reject(&:blank?).join(':')
      end
    end
  end
end
