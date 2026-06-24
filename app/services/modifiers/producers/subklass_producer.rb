# frozen_string_literal: true

module Modifiers
  module Producers
    # SubklassProducer — gera Modifiers a partir das subclasses (`SubKlass`) do
    # personagem, lendo o `levels_json` (fonte de verdade vinda do YAML
    # `config/subclass_overrides.yml`).
    #
    # Cobre hoje:
    # - `grants.movement.walk_bonus_ft` → bonus de deslocamento (ex.: Batedor
    #   nv 7 "Movimento de Batedor" → +10 ft).
    # - `grants.defenses.resistance` → resistência a dano (R5). Ex.: Bruxo
    #   patrono-morte "Cria da Não-Vida" nv1 → necrótico/veneno; Feiticeiro
    #   origem-abissal "Linhagem Demoníaca" nv1 → fogo.
    # - `grants.defenses.immunity` → imunidade a dano. Ex.: Feiticeiro
    #   origem-mutavel "Metabolismo Resistente" nv14 → doenças/veneno.
    # - `grants.defenses.conditions_immunity` (alias plural visto no YAML) →
    #   imunidade a condição.
    #
    # Os modifiers de defesa usam o MESMO canal que o EquippedItemProducer:
    # targets `resistance.<tipo>` / `damage_immunity.<tipo>` /
    # `condition_immunity.<cond>` com `op: :grant`. O
    # CharacterSheetSummaryService lê via `modifier_bag.granted('resistance')`
    # → `modifiers.resistances` (idem damage_immunity / condition_immunity).
    #
    # NÃO emitimos aqui (de propósito):
    # - `grants.languages` e `grants.proficiencies.skills/expertise` — já são
    #   materializados pela onda R4 em `CharacterSheetSummaryService#build_proficiencies`
    #   (lê levels_json, row-level E feature-level), alimentando
    #   `proficiencies.languages` e `proficiencies.skills.subclass`. Não há
    #   consumidor desses valores via modifier bag; emiti-los aqui seria
    #   inerte e duplicaria a fonte de verdade.
    # - `grants.proficiencies.{armor,weapons,tools}` — idem R4.
    # - Recursos de subclasse (rage variants, ki extras, channel divinity).
    #
    # D6 (RESOLVIDO): grants condicionais em `choices.*.options[].grants` (ex.:
    # Bruxo Supragênio — resistência/idioma dependem do gênio escolhido). O
    # importador JÁ propaga o nó `choices` top-level para o `levels_json` (no
    # row do choose_level, via apply_subclass_grants!), então os dados chegam ao
    # producer. Aqui resolvemos a OPÇÃO SELECIONADA pelo jogador (em
    # `metadata.class_choices.per_level[<nível>][<grupo>]`) e aplicamos apenas o
    # `grants.defenses` daquela opção. Sem seleção persistida → não aplica
    # nenhuma (nunca concede as 4 resistências de gênio de uma vez).
    #
    # Bug de origem (movement): ficha do Adimael (Patrulheiro/Batedor nv 9)
    # mostrava speed=45 (35 base + 10 do feat Mobilidade) em vez de 55, porque
    # ninguem estava emitindo o +10 da subclasse.
    #
    # Convencoes:
    # - `source_kind: :subklass` — para a UI separar a origem dos +ft no
    #   breakdown ("Mobilidade vs Movimento de Batedor").
    # - `stacking_type` default ('untyped'): subclass + feat + race somam.
    class SubklassProducer < BaseProducer
      def produce
        out = []
        sheet.sheet_klasses.each do |sk|
          sub = sk.sub_klass
          next unless sub
          rows = parse_levels_json(sub)
          next if rows.empty?

          rows.each do |row|
            row_lvl = row['level'].to_i
            next if row_lvl <= 0 || row_lvl > sk.level.to_i

            # Os grants podem aparecer em dois lugares no YAML
            # (config/subclass_overrides.yml):
            #   1. row['grants']           — grant do nivel inteiro
            #   2. row['features'][i]['grants'] — grant atrelado a uma feature
            # Os dois sao validos; o YAML do Batedor usa (2) para o
            # "Movimento de Batedor" no nv 7 (walk_bonus_ft: 10).
            row_grants = row['grants']
            if row_grants.is_a?(Hash)
              out.concat(movement_grants(sub, row_lvl, row_grants))
              out.concat(defenses_grants(sub, row_lvl, row_grants))
            end

            Array(row['features']).each do |feat|
              next unless feat.is_a?(Hash)
              fgrants = feat['grants']
              next unless fgrants.is_a?(Hash)
              out.concat(movement_grants(sub, row_lvl, fgrants, feature_name: feat['name']))
              out.concat(defenses_grants(sub, row_lvl, fgrants, feature_name: feat['name']))
            end

            # D6 — grants condicionais por OPÇÃO escolhida (choices.*.options[]).
            row_choices = row['choices']
            out.concat(choice_option_grants(sk, sub, row_lvl, row_choices)) if row_choices.is_a?(Hash)
          end
        end
        out
      end

      protected

      def source_kind
        :subklass
      end

      private

      def parse_levels_json(sub)
        raw = sub.levels_json.presence
        return [] if raw.blank?
        parsed = JSON.parse(raw) rescue []
        Array(parsed).select { |r| r.is_a?(Hash) && r['level'].to_i.positive? }
      end

      def movement_grants(sub, row_lvl, grants, feature_name: nil)
        out = []
        movement = grants['movement']
        return out unless movement.is_a?(Hash)

        walk_bonus_ft = movement['walk_bonus_ft'].to_i
        if walk_bonus_ft.positive?
          source = ["subklass", sub.api_index, "movement", "nv#{row_lvl}"]
          source << feature_name.to_s.parameterize if feature_name.present?
          label = feature_name.presence || "#{sub.name} nv #{row_lvl}"
          out << mod(
            target: 'speed',
            op: :add,
            value: walk_bonus_ft,
            source: source.join(':'),
            note: "#{label}: +#{walk_bonus_ft} ft de deslocamento",
          )
        end
        out
      end

      # R5 — Traduz `grants.defenses.*` em modifiers de resistência/imunidade,
      # no MESMO canal que o EquippedItemProducer (targets `resistance.<tipo>`,
      # `damage_immunity.<tipo>`, `condition_immunity.<cond>` com `op: :grant`).
      #
      # Shapes aceitos no YAML (config/subclass_overrides.yml):
      #   grants: { defenses: { resistance: ["necrótico","veneno"] } }  # patrono-morte
      #   grants: { defenses: { immunity:   ["doenças","veneno"] } }    # origem-mutavel
      #   grants: { defenses: { conditions_immunity: ["..."] } }        # alias plural
      def defenses_grants(sub, row_lvl, grants, feature_name: nil)
        defenses = grants['defenses'] || grants[:defenses]
        return [] unless defenses.is_a?(Hash)

        out = []
        label = feature_name.presence || "#{sub.name} nv #{row_lvl}"
        feat_slug = feature_name.present? ? feature_name.to_s.parameterize : nil

        damage_types(defenses['resistance'] || defenses[:resistance]).each do |t|
          out << mod(
            target: "resistance.#{t}",
            op: :grant,
            value: t,
            source: defense_source(sub, 'resistance', t, row_lvl, feat_slug),
            note: "#{label}: resistência a dano de #{t}",
          )
        end

        damage_types(defenses['immunity'] || defenses[:immunity]).each do |t|
          out << mod(
            target: "damage_immunity.#{t}",
            op: :grant,
            value: t,
            source: defense_source(sub, 'immunity', t, row_lvl, feat_slug),
            note: "#{label}: imunidade a dano de #{t}",
          )
        end

        cond_raw = defenses['conditions_immunity'] || defenses[:conditions_immunity] ||
                   defenses['condition_immunity'] || defenses[:condition_immunity]
        damage_types(cond_raw).each do |c|
          out << mod(
            target: "condition_immunity.#{c}",
            op: :grant,
            value: c,
            source: defense_source(sub, 'condition_immunity', c, row_lvl, feat_slug),
            note: "#{label}: imune à condição #{c}",
          )
        end

        out
      end

      # D6 — Para cada grupo de escolha (ex.: `genie_lineage`) no row, resolve a
      # opção que o jogador selecionou e emite os `grants.defenses` dela. A
      # seleção é lida da metadata da ficha; sem seleção → não emite nada
      # (evita conceder as resistências de todas as opções de uma vez).
      def choice_option_grants(sk, sub, row_lvl, choices)
        out = []
        choices.each do |group_key, group|
          next unless group.is_a?(Hash)
          options = group['options'] || group[:options]
          next unless options.is_a?(Array)

          selected_id = selected_option_id(sk, group_key, row_lvl)
          next if selected_id.blank?

          opt = options.find { |o| o.is_a?(Hash) && o['id'].to_s == selected_id.to_s }
          next unless opt
          grants = opt['grants'] || opt[:grants]
          next unless grants.is_a?(Hash)

          label = (opt['name'] || opt['id'] || group_key).to_s
          out.concat(defenses_grants(sub, row_lvl, grants, feature_name: label))
        end
        out
      end

      # Lê a opção selecionada pelo jogador para um grupo de escolha de
      # subclasse. Fontes (em ordem):
      #   metadata.class_choices.per_level[<nível>][<grupo>]
      #   metadata.class_choices[<grupo>]
      # Aceita string (id) ou Array/Hash (usa o 1º id).
      def selected_option_id(sk, group_key, row_lvl)
        meta = (sheet.metadata || {})
        cc = meta['class_choices'] || meta[:class_choices] || {}
        per = cc['per_level'] || cc[:per_level] || {}
        raw = (per[row_lvl.to_s] || per[row_lvl] || {})[group_key.to_s]
        raw = cc[group_key.to_s] if raw.blank?
        extract_option_id(raw)
      end

      def extract_option_id(raw)
        case raw
        when String then raw.strip.presence
        when Array  then extract_option_id(raw.first)
        when Hash   then (raw['id'] || raw[:id] || raw['option'] || raw[:option]).to_s.presence
        else nil
        end
      end

      def damage_types(raw)
        Array(raw).map { |t| t.to_s.strip }.reject(&:empty?)
      end

      def defense_source(sub, kind, type, row_lvl, feat_slug)
        parts = ["subklass", sub.api_index, kind, type.parameterize, "nv#{row_lvl}"]
        parts << feat_slug if feat_slug.present?
        parts.join(':')
      end
    end
  end
end
