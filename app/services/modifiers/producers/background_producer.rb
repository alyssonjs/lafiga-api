# frozen_string_literal: true

module Modifiers
  module Producers
    # BackgroundProducer — gera Modifiers a partir do ANTECEDENTE do personagem (09/10; L0.9, plano A20, Nível 1),
    # lendo os `grants:` da regra do antecedente (`BackgroundRules.find`: o catálogo, as linhas de `backgrounds.rules` e
    # as variações, já fundidas). É o molde do RaceProducer: até aqui o antecedente era dado bem modelado e zero
    # mecânica, e a feature só sobrevivia como TEXTO.
    #
    # Shapes lidos do `grants:`, todos OPCIONAIS:
    #   grants:
    #     defenses:
    #       resistance: [...]           # → resistance.<tipo>         (op :grant)
    #       immunity:   [...]           # → damage_immunity.<tipo>    (op :grant)
    #       conditions_immunity: [...]  # → condition_immunity.<cond> (op :grant)
    #     advantages:
    #       saves:  [...]               # → advantage.save            (op :grant) — incondicional
    #       skills: [...]               # → advantage.skill           (op :grant) — incondicional
    #     situacionais:                 # → situational_advantage.skill (op :grant), o caso comum do Nível 1:
    #       - { pericia: Persuasão, quando: com a nobreza }
    #
    # A vantagem SITUACIONAL é um marcador honesto, não automação: ela depende da cena (o Mestre, ou a mesa, decide se
    # vale), então sai num alvo próprio (`situational_advantage.`), fora do `advantage.skill` incondicional, e o resumo
    # da ficha a publica em `modifiers.situational_advantages` com a perícia, a condição e a fonte.
    #
    # Convenções: `source_kind: :background`; producer PURO; devolve [] sem antecedente ou em erro.
    class BackgroundProducer < BaseProducer
      def produce
        key = background_key
        return [] if key.blank?

        regra = BackgroundRules.find(key)
        return [] unless regra.is_a?(Hash)

        grants = regra[:grants] || regra['grants']
        return [] unless grants.is_a?(Hash)

        nome = (regra[:name] || regra['name'] || key).to_s
        defesas(key, grants) + vantagens(key, grants) + situacionais(key, nome, grants)
      rescue StandardError => e
        Rails.logger.warn("BackgroundProducer: falhou para sheet ##{sheet&.id}: #{e.class}: #{e.message}")
        []
      end

      protected

      def source_kind
        :background
      end

      private

      def background_key
        sheet.background_key.presence || sheet.background&.api_index
      end

      def defesas(key, grants)
        d = grants[:defenses] || grants['defenses']
        return [] unless d.is_a?(Hash)

        lista(d, :resistance).map { |t| grant("resistance.#{t}", t, key, "Resistência a dano de #{t}") } +
          lista(d, :immunity).map { |t| grant("damage_immunity.#{t}", t, key, "Imunidade a dano de #{t}") } +
          lista(d, :conditions_immunity).map { |c| grant("condition_immunity.#{c}", c, key, "Imune à condição #{c}") }
      end

      def vantagens(key, grants)
        a = grants[:advantages] || grants['advantages']
        return [] unless a.is_a?(Hash)

        lista(a, :saves).map { |l| grant('advantage.save', l, key, "Vantagem em testes de resistência vs #{l}") } +
          lista(a, :skills).map { |l| grant('advantage.skill', l, key, "Vantagem em #{l}") }
      end

      def situacionais(key, nome, grants)
        Array(grants[:situacionais] || grants['situacionais']).filter_map do |s|
          s = s.to_h.stringify_keys
          pericia = s['pericia'].to_s.strip
          quando = s['quando'].to_s.strip
          next if pericia.empty? || quando.empty?

          mod(target: 'situational_advantage.skill', op: :grant,
              value: { 'pericia' => pericia, 'quando' => quando, 'fonte' => nome },
              source: ['background', key, 'situacional', pericia.parameterize].join(':'),
              note: "Vantagem em #{pericia} #{quando} (#{nome})")
        end
      end

      def lista(hash, chave)
        Array(hash[chave] || hash[chave.to_s]).map { |v| v.to_s.strip }.reject(&:empty?)
      end

      def grant(target, value, key, note)
        mod(target: target, op: :grant, value: value, source: ['background', key, target, value.to_s.parameterize].join(':'),
            note: note)
      end
    end
  end
end
