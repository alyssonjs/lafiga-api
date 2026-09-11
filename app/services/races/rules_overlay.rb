# frozen_string_literal: true

module Races
  # Sanitiza o `rules_json` que o mestre grava pelo editor de raças.
  #
  # ⚠️ Isto é a fronteira. `RaceRules.apply` é lido em runtime pelo
  # provisioning, pelo level-up, pelas magias raciais e pelo summary — um
  # `rules_json` com forma errada não quebra "a raça do mestre", quebra a
  # CRIAÇÃO DE PERSONAGEM. Por isso só passa o que está no vocabulário, e o
  # resto é recusado com mensagem, nunca engolido.
  #
  # A forma é a MESMA do nó YAML, de propósito: o leitor trata as duas origens
  # sem tradutor no meio, e tradutor é onde nascem as divergências.
  module RulesOverlay
    # Chaves que uma raça (ou sub-raça) pode declarar.
    CHAVES = %w[
      name description size speed darkvision ability languages proficiencies
      traits custom_traits requires
    ].freeze

    # Os canais de `grants` que o runtime realmente consome. Medido no YAML:
    # defenses, spells, advantages, natural_weapon, uses, dc, movement,
    # hp_per_level — mais `options`, que é escolha e não concessão.
    CANAIS = %w[
      defenses advantages movement spells natural_weapon uses dc hp_per_level
    ].freeze

    TIPOS_DE_ABILITY = %w[fixed halfElf variantHuman].freeze
    ATRIBUTOS = %w[FOR DES CON INT SAB CAR STR DEX WIS CHA].freeze

    module_function

    # Devolve `[hash_limpo, erros]`.
    def sanitize(raw)
      erros = []
      bruto = normaliza(raw)
      return [{}, ['rules_json tem de ser um objeto']] unless bruto.is_a?(Hash)

      fora = bruto.keys.map(&:to_s) - CHAVES
      erros << "chaves desconhecidas: #{fora.join(', ')}" if fora.any?

      out = {}
      CHAVES.each do |chave|
        next unless bruto.key?(chave)

        valor = bruto[chave]
        # ⚠️ `nil` é o gesto de SOLTAR a chave — ela volta a valer o YAML. É
        # diferente de gravar vazio, que seria "a raça não tem isto".
        next if valor.nil?

        limpo, e = limpa_chave(chave, valor)
        erros.concat(e)
        out[chave] = limpo unless limpo.nil?
      end

      [erros.any? ? {} : out, erros]
    end

    def limpa_chave(chave, valor)
      case chave
      when 'name', 'description', 'size', 'speed', 'requires'
        [valor.to_s.strip.presence, []]
      when 'darkvision'
        n = valor.to_s.strip
        n.empty? ? [nil, []] : [n.to_i, (n.to_i.negative? ? ["darkvision inválida: #{valor}"] : [])]
      when 'ability'      then limpa_ability(valor)
      when 'languages'    then limpa_languages(valor)
      when 'proficiencies' then limpa_proficiencies(valor)
      when 'traits'       then limpa_traits(valor)
      when 'custom_traits' then limpa_custom_traits(valor)
      else [nil, []]
      end
    end

    def limpa_ability(valor)
      return [nil, ['ability tem de ser um objeto']] unless valor.is_a?(Hash)

      h = valor.stringify_keys
      tipo = h['type'].to_s.presence || 'fixed'
      return [nil, ["tipo de ability inválido: #{tipo}"]] unless TIPOS_DE_ABILITY.include?(tipo)

      erros = []
      out = { 'type' => tipo }

      %w[increases fixed].each do |campo|
        next unless h.key?(campo)

        linhas = Array(h[campo]).filter_map do |linha|
          l = linha.respond_to?(:stringify_keys) ? linha.stringify_keys : {}
          atributo = l['ability'].to_s.upcase
          unless ATRIBUTOS.include?(atributo)
            erros << "atributo desconhecido: #{l['ability']}"
            next
          end
          { 'ability' => atributo, 'amount' => l['amount'].to_i }
        end
        out[campo] = linhas
      end

      if h['choose'].is_a?(Hash)
        c = h['choose'].stringify_keys
        out['choose'] = { 'count' => c['count'].to_i, 'amount' => (c['amount'] || 1).to_i }
      end

      [out, erros]
    end

    def limpa_languages(valor)
      return [nil, ['languages tem de ser um objeto']] unless valor.is_a?(Hash)

      h = valor.stringify_keys
      out = { 'always' => Array(h['always']).map { |v| v.to_s.strip }.reject(&:empty?) }
      out['choiceCount'] = h['choiceCount'].to_i if h.key?('choiceCount')
      lista = Array(h['choiceList']).map { |v| v.to_s.strip }.reject(&:empty?)
      out['choiceList'] = lista if lista.any?
      [out, []]
    end

    def limpa_proficiencies(valor)
      return [nil, ['proficiencies tem de ser um objeto']] unless valor.is_a?(Hash)

      out = {}
      valor.stringify_keys.each do |tipo, corpo|
        out[tipo] = if corpo.is_a?(Hash)
                      c = corpo.stringify_keys
                      {
                        'choiceCount' => c['choiceCount'].to_i,
                        'choices' => Array(c['choices']).map { |v| v.to_s.strip }.reject(&:empty?)
                      }
                    else
                      Array(corpo).map { |v| v.to_s.strip }.reject(&:empty?)
                    end
      end
      [out, []]
    end

    # ⚠️ Trait é REFERÊNCIA por chave, mais campos extras que o traço usa para
    # interpolar (o `damage` da ancestralidade do Draconato vira `<damage>` na
    # descrição). Perder os extras deixaria os Draconatos sem tipo de dano.
    def limpa_traits(valor)
      erros = []
      linhas = Array(valor).filter_map do |linha|
        l = linha.is_a?(Hash) ? linha.stringify_keys : { 'key' => linha.to_s }
        chave = l['key'].to_s.strip
        if chave.empty?
          erros << 'traço sem `key`'
          next
        end
        extras = l.except('key').transform_values { |v| v.is_a?(String) ? v.strip : v }
        { 'key' => chave }.merge(extras)
      end
      [linhas, erros]
    end

    def limpa_custom_traits(valor)
      return [nil, ['custom_traits tem de ser um objeto']] unless valor.is_a?(Hash)

      erros = []
      out = {}
      valor.stringify_keys.each do |chave, corpo|
        k = chave.to_s.strip
        unless k.match?(/\A[a-z0-9_]+\z/)
          erros << "chave de traço inválida: #{chave.inspect} (use minúsculas, números e _)"
          next
        end
        unless corpo.is_a?(Hash)
          erros << "traço #{k} tem de ser um objeto"
          next
        end

        c = corpo.stringify_keys
        linha = {
          'name' => c['name'].to_s.strip,
          'description' => c['description'].to_s.strip
        }.reject { |_, v| v.empty? }
        erros << "traço #{k} precisa de nome" if linha['name'].blank?

        if c['grants'].is_a?(Hash)
          g, e = limpa_grants(k, c['grants'])
          erros.concat(e)
          linha['grants'] = g if g.present?
        end
        linha['sheet_impact'] = c['sheet_impact'].to_s.strip if c['sheet_impact'].present?
        linha['options'] = c['options'] if c['options'].is_a?(Hash)

        out[k] = linha
      end
      [out, erros]
    end

    # ⚠️ Só os canais que o runtime consome. Um canal inventado seria gravado e
    # IGNORADO — o mestre configuraria a resistência e ela não valeria, sem
    # nada a dizer porquê. É o modo de falha silencioso de sempre.
    def limpa_grants(chave_traco, grants)
      erros = []
      out = {}
      grants.stringify_keys.each do |canal, corpo|
        unless CANAIS.include?(canal)
          erros << "traço #{chave_traco}: canal de grant desconhecido #{canal.inspect}"
          next
        end
        out[canal] = corpo
      end
      [out, erros]
    end

    def normaliza(raw)
      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      h.is_a?(Hash) ? h.deep_stringify_keys : h
    end
  end
end
