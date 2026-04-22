# frozen_string_literal: true

module Modifiers
  module Producers
    # KlassProducer — gera Modifiers a partir das classes (e níveis) da sheet.
    #
    # Cobre:
    # - Saving throw proficiencies (ex.: Bárbaro = STR/CON)
    # - Movimento Rápido (Bárbaro nv 5+, sem armadura pesada)
    # - Unarmored Movement (Monge — bonus_ft progressivo)
    #
    # Não cobre ainda (ficam com ClassRules legado):
    # - Recursos de classe (rage, ki, second_wind)
    # - Spell slots / cantrip count
    # - Subclass-specific (vai pro SubklassProducer na fase seguinte)
    class KlassProducer < BaseProducer
      ABBREV_TO_KEY = {
        'FOR' => 'str', 'STR' => 'str',
        'DES' => 'dex', 'DEX' => 'dex',
        'CON' => 'con',
        'INT' => 'int',
        'SAB' => 'wis', 'WIS' => 'wis',
        'CAR' => 'cha', 'CHA' => 'cha',
      }.freeze

      def produce
        out = []
        sheet.sheet_klasses.each do |sk|
          next unless sk.klass
          rule = ClassRules.find(sk.klass.api_index) || {}
          out.concat(saving_throw_grants(sk, rule))
          out.concat(movement_features(sk, rule))
        end
        out
      end

      protected

      def source_kind
        :klass
      end

      private

      def saving_throw_grants(sk, rule)
        Array(rule[:saving_throws]).filter_map do |st|
          raw = st.to_s.upcase.strip
          key = ABBREV_TO_KEY[raw]
          next nil unless key
          mod(
            target: "save.#{key}",
            op: :grant,
            value: key,
            source: "klass:#{sk.klass.api_index}",
            note: "#{sk.klass.name} concede proficiência em salvaguarda de #{key.upcase}",
          )
        end
      end

      def movement_features(sk, rule)
        out = []
        level = sk.level.to_i
        # ClassRules define essas features em `feature_rules:` (ver class_rules.rb).
        # Mantemos fallback em `features` para compatibilidade com seeds antigos.
        fr = (rule[:feature_rules] || rule['feature_rules'] ||
              rule[:features]      || rule['features']      || {})

        # Movimento Rápido (Bárbaro nv 5+; bloqueado por armadura pesada)
        fm = fr[:fast_movement] || fr['fast_movement']
        if fm
          fm_level = (fm[:level] || fm['level'] || 5).to_i
          fm_add   = (fm[:add]   || fm['add']   || 0).to_i
          armor_cat = current_armor_category
          blocked_when_heavy = (
            (fm.dig(:unless, :armor_category) || fm.dig('unless', 'armor_category')).to_s == 'heavy'
          )
          if level >= fm_level && fm_add > 0 && !(blocked_when_heavy && armor_cat == 'heavy')
            # NOTA: ClassRules.fast_movement é em metros; convertemos para ft (~3.28)
            out << mod(
              target: 'speed',
              op: :add,
              value: (fm_add * 3.28).round,
              source: "klass:#{sk.klass.api_index}:fast_movement",
              note: "Movimento Rápido (#{sk.klass.name} nv #{fm_level}): +#{fm_add}m",
            )
          end
        end

        # Unarmored Movement (Monge): tabela bonus_ft_by_level
        uam = fr[:unarmored_movement] || fr['unarmored_movement']
        if uam
          armor_cat = current_armor_category
          if armor_cat == 'none'
            table = uam[:bonus_ft_by_level] || uam['bonus_ft_by_level'] || {}
            bonus_ft = 0
            table.each do |lvl, ft|
              bonus_ft = [bonus_ft, ft.to_i].max if level >= lvl.to_i
            end
            if bonus_ft > 0
              out << mod(
                target: 'speed',
                op: :add,
                value: bonus_ft,
                source: "klass:#{sk.klass.api_index}:unarmored_movement",
                note: "Movimento sem Armadura (#{sk.klass.name}): +#{bonus_ft} ft",
              )
            end
          end
        end

        out
      end

      def current_armor_category
        eq = context[:equipment]
        return 'none' unless eq
        ((eq[:ac] || eq['ac'] || {})[:armor_category] || (eq[:ac] || eq['ac'] || {})['armor_category']).to_s.downcase.presence || 'none'
      end
    end
  end
end
