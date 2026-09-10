# frozen_string_literal: true

module Spells
  # FASE 1 das magias — LEITURA: de onde vem a magia inata, com que limite e em
  # que modo.
  #
  # O dado sempre existiu. `RaceRules.trait_definitions` guarda os legados com
  # `minimum_level` e `per_long_rest`, `RacialSpellsService` grava
  # `SheetKnownSpell(source: 'race', uses_per_rest: 'LR')`, e a ficha mostrava
  # um chip genérico "RAÇA" e um contador de usos. O que faltava era dizer QUAL
  # raça, QUAL traço e a que custo — "Raio Adoecente — Legado Abissal,
  # 1/descanso longo, nível 3+" em vez de "Raio Adoecente · RAÇA".
  #
  # ⚠️ É REGISTRO, não autoridade. Quem concede a magia continua a ser o
  # `race_rules.yml` via `RacialSpellsService`. Este índice só ANOTA linhas que
  # já existem — se não achar a atrelagem, a linha sai exatamente como saía. É o
  # que mantém a paridade: nenhuma ficha perde nada por este índice falhar.
  #
  # ⚠️ Só anota magia INATA (`Race`/`SubRace`, ou qualquer fonte que não gaste
  # espaço de magia). As 1302 atrelagens de classe com `with_slot` ficam de
  # fora de propósito: anotá-las engordaria o payload de toda ficha de
  # conjurador para dizer o que a coluna de classe já diz.
  class InnateSourceIndex
    # Fontes cujo custo NÃO é um espaço de magia — o "conjura sem espaço" do
    # pedido (tiefling, monge das sombras).
    MODOS_SEM_ESPACO = %w[at_will uses_per_rest resource].freeze

    def initialize(sheet)
      @sheet = sheet
    end

    # `{ spell_id => { origin:, trait:, casting_mode:, cost_label:,
    #                  min_character_level:, label: } }`
    #
    # Vazio quando a ficha não tem raça/sub-raça ou o catálogo não foi semeado —
    # e vazio significa "não anota nada", nunca "apaga".
    def call
      linhas = fontes_da_ficha
      return {} if linhas.empty?

      linhas.each_with_object({}) do |ss, acc|
        # A primeira atrelagem ganha: uma magia inata vem de um traço só, e se
        # vier de dois (Escuridão no Drow e no Infernal) a ficha só tem uma das
        # raças de qualquer modo.
        acc[ss.spell_id] ||= anota(ss)
      end
    end

    private

    # Só as atrelagens que pertencem a ESTA ficha. Uma consulta por tipo, com o
    # id da própria ficha — não varre o catálogo inteiro.
    def fontes_da_ficha
      pares = []
      pares << ['Race', @sheet.race_id] if @sheet.race_id.present?
      pares << ['SubRace', @sheet.sub_race_id] if @sheet.sub_race_id.present?
      return [] if pares.empty?

      escopo = pares.map { |t, i| SpellSource.where(source_type: t, source_id: i) }.reduce(:or)
      escopo.includes(:spell).to_a
    rescue StandardError => e
      # Catálogo ausente ou esquema defasado não pode derrubar a ficha.
      Rails.logger.warn("[InnateSourceIndex] fonte indisponível: #{e.message}")
      []
    end

    def anota(ss)
      origem = nome_da_fonte(ss)
      traco  = nome_do_traco(ss)
      custo  = ss.cost_label

      {
        origin: origem,
        trait: traco,
        casting_mode: ss.casting_mode,
        cost_label: custo,
        min_character_level: ss.min_character_level,
        uses_spell_slot: !MODOS_SEM_ESPACO.include?(ss.casting_mode.to_s),
        label: monta_rotulo(origem, traco, custo, ss.min_character_level, ss.spell&.name)
      }.compact
    end

    def nome_da_fonte(ss)
      alvo = ss.source_type == 'Race' ? Race.find_by(id: ss.source_id) : SubRace.find_by(id: ss.source_id)
      alvo&.name
    end

    # `notes` guarda `"trait: abyssal_legacy"`; o catálogo de definições traduz
    # a chave para "Legado Abissal", que é o nome que a mesa usa.
    def nome_do_traco(ss)
      chave = ss.notes.to_s[/trait:\s*(\S+)/, 1]
      return nil if chave.blank?

      definicoes = RaceRules.trait_definitions || {}
      d = definicoes[chave.to_sym] || definicoes[chave] || {}
      (d[:name] || d['name']).presence
    rescue StandardError
      nil
    end

    # "Legado Abissal, 1/descanso longo, nível 3+"
    # "Tiefling · Presença Sobrenatural, à vontade"
    # "Gnomo da Floresta, à vontade"
    #
    # A procedência é o que o jogador precisa de ver; o traço só entra quando
    # acrescenta. Duas armadilhas medidas em dados reais:
    #
    #   · o traço `minor_illusion_cantrip` chama-se "Truque: Ilusão Menor" e a
    #     magia chama-se "Ilusão Menor" — repetir o nome não informa nada;
    #   · o traço "Legado Abissal" já contém a sub-raça "Abissal", e
    #     "Abissal · Legado Abissal" é ruído.
    def monta_rotulo(origem, traco, custo, nivel_min, nome_magia)
      partes = [procedencia(origem, traco, nome_magia), custo.presence]
      partes << "nível #{nivel_min}+" if nivel_min.to_i > 1
      partes.compact.join(', ').presence
    end

    def procedencia(origem, traco, nome_magia)
      t = traco.presence
      o = origem.presence
      # traço que só repete o nome da magia não acrescenta
      t = nil if t && nome_magia.present? && dobra?(t, nome_magia)
      return o if t.nil?
      return t if o.nil? || dobra?(t, o)

      "#{o} · #{t}"
    end

    # Um contém o outro, ignorando acento e caixa.
    def dobra?(a, b)
      x = achata(a)
      y = achata(b)
      return false if x.blank? || y.blank?

      x.include?(y) || y.include?(x)
    end

    def achata(v)
      ActiveSupport::Inflector.transliterate(v.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').strip
    end
  end
end
