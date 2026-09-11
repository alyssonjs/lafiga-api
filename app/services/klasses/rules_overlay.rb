# frozen_string_literal: true

module Klasses
  # Sanitiza o `klasses.rules` que o mestre grava pelo editor de classes.
  #
  # ⚠️ Isto é a fronteira, e ela estava ABERTA: o controller admitia
  # `rules: {}` no `permit` — forma livre, sem validação — e
  # `KlassDbRulesContract` existia mas tinha ZERO chamadas no caminho de
  # escrita (só uma rake manual e o próprio spec).
  #
  # Somado ao replace-all de `ClassRules.find`, um PATCH com meia classe
  # apagava a outra metade: `hit_die`, proficiências, `features_level1`,
  # `subclass` e `feature_rules` sumiam para todos os personagens dela, em
  # silêncio. A fase 1 fecha as duas pontas — aqui e na sobreposição.
  #
  # O vocabulário são as 17 chaves MEDIDAS em `ClassRules::CLASS_RULES`
  # (12 presentes nas 13 classes; `spellcasting` em 9, `starting_gold` em 7,
  # `starting_equipment` em 4, `resources` em 2).
  module RulesOverlay
    CHAVES = %w[
      id name hit_die primary_abilities saving_throws
      armor_proficiencies weapon_proficiencies tool_proficiencies
      skill_proficiencies features_level1 subclass
      required_choices_at_level feature_rules spellcasting
      starting_gold starting_equipment resources
    ].freeze

    # Listas de texto simples — o resto tem forma própria.
    LISTAS = %w[
      primary_abilities saving_throws armor_proficiencies
      weapon_proficiencies tool_proficiencies features_level1
    ].freeze

    # ⚠️ `saving_throws` e `primary_abilities` viajam em SIGLA (`FOR`), não no
    # nome por extenso. A auditoria da fase 0 mediu as duas grafias em
    # desacordo nas 13, e `SavingThrowsCatalog` só cobre EN→PT — não atravessa
    # `Força` → `FOR`. Aqui fica o escritor canônico que faltava.
    SIGLA = {
      'forca' => 'FOR', 'for' => 'FOR', 'str' => 'FOR',
      'destreza' => 'DES', 'des' => 'DES', 'dex' => 'DES',
      'constituicao' => 'CON', 'con' => 'CON',
      'inteligencia' => 'INT', 'int' => 'INT',
      'sabedoria' => 'SAB', 'sab' => 'SAB', 'wis' => 'SAB',
      'carisma' => 'CAR', 'car' => 'CAR', 'cha' => 'CAR'
    }.freeze

    ATRIBUTOS = %w[FOR DES CON INT SAB CAR].freeze

    module_function

    # Devolve `[hash_limpo, erros]`. Com qualquer erro devolve `[{}, erros]`:
    # nada fica gravado pela metade.
    def sanitize(raw)
      erros = []
      bruto = normaliza(raw)
      return [{}, ['rules tem de ser um objeto']] unless bruto.is_a?(Hash)

      fora = bruto.keys.map(&:to_s) - CHAVES
      erros << "chaves desconhecidas: #{fora.join(', ')}" if fora.any?

      out = {}
      CHAVES.each do |chave|
        next unless bruto.key?(chave)

        valor = bruto[chave]
        # ⚠️ `nil` é o gesto de SOLTAR a chave — ela volta a valer a regra em
        # código. É diferente de gravar vazio, que seria "a classe não tem".
        next if valor.nil?

        limpo, e = limpa_chave(chave, valor)
        erros.concat(e)
        out[chave] = limpo unless limpo.nil?
      end

      [erros.any? ? {} : out, erros]
    end

    def limpa_chave(chave, valor)
      case chave
      when 'id', 'name', 'starting_gold' then [valor.to_s.strip.presence, []]
      when 'hit_die' then limpa_hit_die(valor)
      when 'primary_abilities', 'saving_throws' then limpa_atributos(chave, valor)
      when *LISTAS then [lista_de_textos(valor), []]
      when 'skill_proficiencies' then limpa_escolha(chave, valor)
      when 'subclass' then limpa_subclass(valor)
      # ⚠️ `feature_rules`, `required_choices_at_level`, `spellcasting`,
      # `starting_equipment` e `resources` passam como objeto livre DE
      # PROPÓSITO: são o catálogo que o motor de combate consome, com forma
      # por feature, e inventar um esquema agora desligaria mecânica em
      # silêncio. A fase 6 do plano trata deles, com auditoria antes.
      else [valor.is_a?(Hash) || valor.is_a?(Array) ? valor : nil,
            valor.is_a?(Hash) || valor.is_a?(Array) ? [] : ["#{chave} tem de ser objeto ou lista"]]
      end
    end

    # Medido: a regra guarda `"d10"`; a coluna `klasses.hit_die` guarda `10`.
    # Aceita as duas na entrada e GRAVA a forma da regra.
    def limpa_hit_die(valor)
      n = valor.to_s.strip.downcase.delete('d')
      return [nil, []] if n.empty?
      return [nil, ["hit_die inválido: #{valor.inspect}"]] unless n.match?(/\A\d+\z/) && n.to_i.positive?

      ["d#{n.to_i}", []]
    end

    def limpa_atributos(chave, valor)
      brutos = lista_de_textos(valor)
      siglas = brutos.map { |v| SIGLA[sem_acento(v)] || v.to_s.upcase }
      fora = siglas.reject { |v| ATRIBUTOS.include?(v) }
      return [nil, ["#{chave}: atributo desconhecido #{fora.join(', ')}"]] if fora.any?

      [siglas.uniq, []]
    end

    # `{choose: N, options: [...]}` — a forma medida de `skill_proficiencies`.
    def limpa_escolha(chave, valor)
      return [nil, ["#{chave} tem de ser um objeto"]] unless valor.is_a?(Hash)

      c = valor.stringify_keys
      escolhe = c['choose'].to_i
      opcoes = lista_de_textos(c['options'])
      return [nil, ["#{chave}: `choose` #{escolhe} sem opções suficientes"]] if escolhe > opcoes.size

      [{ 'choose' => escolhe, 'options' => opcoes }, []]
    end

    # `{choose_level: N, options: {slug => {id, name}}}`.
    def limpa_subclass(valor)
      return [nil, ['subclass tem de ser um objeto']] unless valor.is_a?(Hash)

      c = valor.stringify_keys
      nivel = c['choose_level'].to_i
      return [nil, ["subclass: `choose_level` inválido (#{c['choose_level'].inspect})"]] unless nivel.positive?

      opcoes = {}
      (c['options'] || {}).each do |slug, corpo|
        chave = slug.to_s.strip
        next if chave.empty?

        d = corpo.is_a?(Hash) ? corpo.stringify_keys : {}
        opcoes[chave] = { 'id' => (d['id'].presence || chave).to_s, 'name' => d['name'].to_s.strip }
      end
      [{ 'choose_level' => nivel, 'options' => opcoes }, []]
    end

    def lista_de_textos(valor)
      Array(valor).map { |v| v.to_s.strip }.reject(&:empty?)
    end

    def sem_acento(valor)
      valor.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
    end

    def normaliza(raw)
      return raw.to_unsafe_h.deep_stringify_keys if raw.respond_to?(:to_unsafe_h)
      return raw.deep_stringify_keys if raw.is_a?(Hash)

      raw
    end
  end
end
