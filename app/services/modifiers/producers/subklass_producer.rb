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
    #
    # NÃO cobre ainda (deixar explicito para futura extensão):
    # - `grants.proficiencies.armor/weapons/skills` (ja merge-ados em
    #   `CharacterSheetSummaryService#build_proficiencies`).
    # - `grants.advantages.*`, `grants.languages.*`, etc.
    # - Recursos de subclasse (rage variants, ki extras, channel divinity).
    #
    # Bug de origem: ficha do Adimael (Patrulheiro/Batedor nv 9) mostrava
    # speed=45 (35 base + 10 do feat Mobilidade) em vez de 55, porque ninguem
    # estava emitindo o +10 da subclasse.
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
            out.concat(movement_grants(sub, row_lvl, row_grants)) if row_grants.is_a?(Hash)

            Array(row['features']).each do |feat|
              next unless feat.is_a?(Hash)
              fgrants = feat['grants']
              out.concat(movement_grants(sub, row_lvl, fgrants, feature_name: feat['name'])) if fgrants.is_a?(Hash)
            end
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
    end
  end
end
