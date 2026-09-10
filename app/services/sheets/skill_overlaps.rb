# frozen_string_literal: true

require 'json'

module Sheets
  # SOBREPOSIÇÃO de perícia: a subclasse concede uma perícia que o personagem
  # já tinha escolhido na classe.
  #
  # ⚠️ Pela regra de 5e, uma feature que concede algo que você já tem deixa-o
  # escolher outra coisa. A aplicação não detectava isso, e o resultado é uma
  # escolha DESPERDIÇADA: o personagem fica com uma perícia a menos do que devia,
  # e nada na tela diz porquê.
  #
  # Medido em 10/09/2026: 1 caso em toda a base (Avalon Mellion — escolheu
  # Arcanismo no nível 1 como mago, e Navegação Planar concedeu Arcanismo no
  # nível 2). Raro, mas silencioso — que é o pior tipo.
  #
  # A reposição fica em `metadata.class_choices.skill_replacements`:
  #
  #   { 'Arcanismo' => 'Intuição' }
  #
  # ⚠️ Guardar a TROCA, e não reescrever a escolha original, é deliberado: a
  # ficha continua a poder dizer o que aconteceu, e desfazer é possível. Se eu
  # sobrescrevesse `class_choices...skills`, a sobreposição desapareceria e
  # ninguém saberia que houve reposição.
  module SkillOverlaps
    module_function

    def normalize(nome)
      nome.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
    end

    def replacements(sheet)
      raw = (sheet.metadata || {}).dig('class_choices', 'skill_replacements')
      raw.is_a?(Hash) ? raw : {}
    end

    # As perícias escolhidas na CLASSE, como o pipeline as grava.
    def class_picks(sheet)
      meta = sheet.metadata || {}
      Array(meta.dig('class_choices', 'per_level', '1', 'skills')).map(&:to_s)
    end

    # O que cada subclasse da ficha concede como perícia FIXA.
    def subclass_grants(sheet)
      SheetKlass.where(sheet_id: sheet.id).filter_map do |sk|
        sub = sk.sub_klass
        next if sub.nil? || sub.levels_json.blank?

        dados = sub.levels_json.is_a?(String) ? (JSON.parse(sub.levels_json) rescue []) : sub.levels_json
        nomes = Array(dados).flat_map do |linha|
          next [] unless linha.is_a?(Hash)

          blocos = [linha['grants']] + Array(linha['features']).map { |f| f.is_a?(Hash) ? f['grants'] : nil }
          blocos.compact.flat_map { |g| Array(g.dig('proficiencies', 'skills')) }
        end.map(&:to_s)
        next if nomes.empty?

        { sub: sub, skills: nomes }
      end
    rescue StandardError
      []
    end

    # ⚠️ Tudo o que o personagem JÁ TEM, de qualquer fonte.
    #
    # A primeira versão só olhava classe + subclasse, e oferecia "História" ao
    # Avalon — que já a tem pelo antecedente Nobre. Escolher lá desperdiçaria a
    # reposição pelo mesmo motivo que criou o problema.
    def owned_skills(sheet)
      meta = sheet.metadata || {}
      bg = meta['background_summary'].is_a?(Hash) ? meta['background_summary'] : (sheet.background_summary || {})
      rs = meta['race_summary'].is_a?(Hash) ? meta['race_summary'] : (sheet.race_summary || {})

      (Array(bg['skills']) +
        Array(rs['skills']) +
        Array(meta.dig('race_choices', 'chosenSkills')).map { |t| t.is_a?(Hash) ? (t['name'] || t['id']) : t }
      ).compact.map(&:to_s)
    rescue StandardError
      []
    end

    # As opções de reposição: a lista da classe menos tudo o que já tem.
    def options_for(sheet, ja_tem)
      sk = SheetKlass.where(sheet_id: sheet.id).order(level: :asc).first
      rule = sk&.klass && (ClassRules.find(sk.klass.api_index) rescue nil)
      return [] unless rule.is_a?(Hash)

      opcoes = rule.dig(:skill_proficiencies, :options) || rule.dig('skill_proficiencies', 'options')
      return [] unless opcoes.is_a?(Array)

      tidos = ja_tem.map { |n| normalize(n) }
      opcoes.map(&:to_s).reject { |o| tidos.include?(normalize(o)) }
    rescue StandardError
      []
    end

    # As sobreposições desta ficha, resolvidas ou não.
    #
    #   [{ 'skill' => 'Arcanismo', 'subclass' => 'Navegação Planar',
    #      'replacement' => 'Intuição' | nil, 'options' => [...] }]
    def detect(sheet)
      escolhidas = class_picks(sheet)
      return [] if escolhidas.empty?

      trocas = replacements(sheet)
      escolhidas_norm = escolhidas.map { |n| normalize(n) }

      subclass_grants(sheet).flat_map do |linha|
        linha[:skills].filter_map do |concedida|
          idx = escolhidas_norm.index(normalize(concedida))
          next if idx.nil?

          original = escolhidas[idx]
          # As opções tiram o que já tem — incluindo a reposição já escolhida,
          # que volta pelo `replacement`.
          ja_tem = escolhidas + linha[:skills] + trocas.values + owned_skills(sheet)
          {
            'skill' => original,
            'subclass' => linha[:sub].name,
            'replacement' => trocas[original],
            'options' => options_for(sheet, ja_tem - [trocas[original]].compact)
          }.compact
        end
      end
    rescue StandardError
      []
    end

    # Aplica as trocas na lista de perícias de CLASSE.
    #
    # ⚠️ Substitui, não acrescenta: a escolha desperdiçada some da fonte `class`
    # e a reposição toma o lugar dela. A perícia original continua na ficha —
    # concedida pela SUBCLASSE, que é de onde ela realmente veio.
    def apply!(sheet, proficiencias)
      trocas = replacements(sheet)
      return proficiencias if trocas.empty?
      return proficiencias unless proficiencias[:skills].is_a?(Hash)

      mapa = trocas.each_with_object({}) { |(de, para), h| h[normalize(de)] = para.to_s }
      lista = Array(proficiencias[:skills][:class])
      proficiencias[:skills][:class] = lista.map { |n| mapa[normalize(n)] || n }.uniq
      proficiencias
    rescue StandardError
      proficiencias
    end
  end
end
