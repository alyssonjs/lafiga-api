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

    # Medido no YAML: só estas quatro existem. `languages` entra porque o
    # summary lê `proficiencies[:languages]` ao montar a ficha.
    CATEGORIAS_DE_PROFICIENCIA = %w[skills tools weapons armor languages].freeze

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
      when 'name', 'description', 'size'
        [valor.to_s.strip.presence, []]
      # ⚠️ MEDIDO no YAML: `speed` é INTEIRO em PÉS nas 14 ocorrências, nenhuma
      # string. Gravar "9m" onde o resto do sistema lê um número não levanta
      # erro — só faz o deslocamento sair errado na ficha, em silêncio.
      when 'speed'
        n = valor.to_s.strip
        return [nil, []] if n.empty?
        return [nil, ["speed tem de ser um número em pés: #{valor}"]] unless n.match?(/\A\d+\z/)

        [n.to_i, []]
      # ⚠️ MEDIDO: `darkvision` é `{range: N}` nas 8 ocorrências, nunca um int
      # solto. Aceita número na entrada (é o que o formulário manda), mas GRAVA
      # a forma do YAML.
      when 'darkvision'
        limpa_darkvision(valor)
      # ⚠️ MEDIDO: `requires` é uma LISTA (`["dwarfTool"]`). A versão anterior
      # gravava a string "[\"dwarfTool\"]".
      when 'requires'
        [lista_de_textos(valor.is_a?(Array) ? valor : [valor]), []]
      when 'ability'      then limpa_ability(valor)
      when 'languages'    then limpa_languages(valor)
      when 'proficiencies' then limpa_proficiencies(valor)
      when 'traits'       then limpa_traits(valor)
      when 'custom_traits' then limpa_custom_traits(valor)
      else [nil, []]
      end
    end

    def limpa_darkvision(valor)
      bruto = valor.is_a?(Hash) ? (valor.stringify_keys['range']) : valor
      n = bruto.to_s.strip
      return [nil, []] if n.empty?
      return [nil, ["darkvision tem de ser um número em pés: #{valor}"]] unless n.match?(/\A\d+\z/)

      [{ 'range' => n.to_i }, []]
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

    # Formas MEDIDAS no YAML (13 raças + sub-raças):
    #   `weapons` / `armor` → lista simples
    #   `skills` / `tools`  → `{fixed: [...]}` OU `{choiceCount: N, choices: [...]}`
    #
    # 🐞 A primeira versão coagia TODO Hash para `{choiceCount, choices}` e
    # atirava fora o `fixed` — que é a forma dominante (6 de 7 em `skills`) e
    # é o que o provisioning lê e reescreve ao resolver a escolha de
    # ferramentas do Anão. O Elfo perderia Percepção no primeiro save que
    # tocasse em proficiências, sem erro nenhum.
    def limpa_proficiencies(valor)
      return [nil, ['proficiencies tem de ser um objeto']] unless valor.is_a?(Hash)

      bruto = valor.stringify_keys
      fora = bruto.keys - CATEGORIAS_DE_PROFICIENCIA
      return [nil, ["categorias de proficiência desconhecidas: #{fora.join(', ')}"]] if fora.any?

      out = {}
      bruto.each do |tipo, corpo|
        out[tipo] = corpo.is_a?(Hash) ? limpa_bloco_de_proficiencia(corpo) : lista_de_textos(corpo)
      end
      [out, []]
    end

    # ⚠️ `fixed` e a escolha CONVIVEM: o Anão tem ferramentas por escolha, o
    # Elfo tem perícia fixa, e nada impede uma raça caseira de ter as duas.
    def limpa_bloco_de_proficiencia(corpo)
      c = corpo.stringify_keys
      bloco = {}
      bloco['fixed'] = lista_de_textos(c['fixed']) if c.key?('fixed')
      if c.key?('choiceCount') || c.key?('choices')
        bloco['choiceCount'] = c['choiceCount'].to_i
        bloco['choices'] = lista_de_textos(c['choices'])
      end
      bloco
    end

    def lista_de_textos(valor)
      Array(valor).map { |v| v.to_s.strip }.reject(&:empty?)
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
