# frozen_string_literal: true

module Sheets
  # Sobrescritas do MESTRE — a ÚLTIMA camada do valor assado.
  #
  # O mestre crava um número (PV máximo, deslocamento, atributo) e ele passa por
  # cima do que o motor calculou. Entra no fim do `CharacterSheetSummaryService`,
  # dentro de `abilities[:scores]`, `movement[:speed_ft]` e `sheet[:hp_max]` — os
  # mesmos campos que o front já lê como BASE. Por isso a sobrescrita chega de
  # graça à ficha, ao card, ao token do mapa e ao combatente novo, sem tocar
  # nenhum dos ~120 pontos que leem esses campos.
  #
  # ⚠️ É camada de BASE, não de runtime: condições e efeitos continuam a valer
  # POR CIMA. Um personagem com deslocamento cravado em 45 ft ainda vai a 0
  # quando fica Agarrado — é o comportamento certo, e é de graça porque o
  # `derivedStatsEngine` já trata estes campos como ponto de partida.
  #
  # ⚠️ NÃO grava nas colunas `str..cha`. Cinco serviços as reescrevem a partir do
  # metadata (`sync_ability_columns_from_metadata!`), e a sobrescrita sumiria no
  # próximo nível ou talento. Ver a migration `add_dm_overrides_to_sheets`.
  module DmOverrides
    ABILITY_KEYS = %w[str dex con int wis cha].freeze
    KEYS = (ABILITY_KEYS + %w[hp_max speed_ft]).freeze

    # Teto de 30 nos atributos, não os 20 de `ABILITY_SCORE_CAP`: aquele é o
    # limite da REGRA de progressão (ASI/half-feat não passam de 20), e a
    # sobrescrita existe justamente para o que a regra não cobre. 30 é o mesmo
    # teto que o `derivedStatsEngine` do front aplica — passar disso daria um
    # número no servidor que a ficha não mostraria.
    ABILITY_CAP = 30

    module_function

    # Normaliza o que veio do controller. Devolve `[hash_limpo, erros]`.
    def sanitize(raw, actor_id: nil, previous: {}, computed: {})
      erros = []
      out = {}
      (raw || {}).each do |key, entry|
        k = key.to_s
        unless KEYS.include?(k)
          erros << "Chave não permitida: #{k}"
          next
        end
        # `nil` é o gesto de REMOVER — o mestre solta o valor e a ficha volta a
        # calcular sozinha.
        if entry.nil?
          out[k] = nil
          next
        end
        h = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
        h = h.is_a?(Hash) ? h.transform_keys(&:to_s) : { 'value' => h }
        valor = clamp(k, h['value'])
        if valor.nil?
          erros << "Valor inválido para #{k}: #{h['value'].inspect}"
          next
        end
        anterior = (previous || {})[k]
        out[k] = {
          'value' => valor,
          # O valor que o motor daria SEM a sobrescrita. Serve a duas coisas: o
          # aviso de defasagem na ficha (quando o personagem sobe de nível e o
          # calculado passa o cravado) e a reconstrução da base no wizard de
          # edição — sem ele, abrir "Editar Personagem" assaria a sobrescrita
          # dentro do atributo para sempre.
          'computed' => (computed || {})[k] || anterior&.dig('computed'),
          'note' => h['note'].presence&.to_s&.slice(0, 240),
          'by_user_id' => actor_id || anterior&.dig('by_user_id'),
          'at' => Time.current.iso8601
        }.compact
      end
      [out, erros]
    end

    # Funde o patch no que já existe; chave com `nil` remove.
    def merge(current, patch)
      base = (current || {}).dup
      (patch || {}).each { |k, v| v.nil? ? base.delete(k) : base[k] = v }
      base
    end

    def clamp(key, raw)
      return nil if raw.nil? || raw.to_s.strip.empty?
      n = Integer(raw.to_s.strip, exception: false)
      return nil if n.nil?
      case key
      when *ABILITY_KEYS then n.clamp(1, ABILITY_CAP)
      when 'hp_max'      then [n, 1].max
      when 'speed_ft'    then [n, 0].max
      end
    end

    # Os valores que o motor calculou, ANTES de qualquer sobrescrita. É o que
    # grava `computed` — chamar sempre com o payload ainda intacto.
    def snapshot_computed(abilities:, movement:, hp_max:)
      out = { 'hp_max' => hp_max.to_i, 'speed_ft' => movement[:speed_ft].to_i }
      ABILITY_KEYS.each { |k| out[k] = (abilities[:scores] || {})[k.to_sym].to_i }
      out
    end

    # Aplica no payload do summary. MUTA `abilities` e `movement` (são hashes de
    # trabalho do próprio serviço) e devolve o `hp_max` efetivo.
    def apply!(overrides, abilities:, movement:, hp_max:)
      ov = overrides || {}
      return hp_max if ov.empty?

      ABILITY_KEYS.each do |k|
        val = ov.dig(k, 'value')
        next if val.nil?
        sym = k.to_sym
        (abilities[:scores] ||= {})[sym] = val.to_i
        (abilities[:mods] ||= {})[sym] = CharacterRules.modifier(val.to_i)
        # O breakdown da ficha já sabe mostrar procedência ("Dado/Base", "Raça",
        # "Talento X"): a sobrescrita entra como mais uma linha, em vez de virar
        # um "Ajuste manual" anônimo de drift.
        linhas = (abilities[:sources] ||= {})[sym] ||= []
        linhas << { label: 'Mestre', val: val.to_i }
      end

      if (spd = ov.dig('speed_ft', 'value'))
        movement[:speed_ft] = spd.to_i
        movement[:speed_m]  = (spd.to_i * 0.3048).round(1)
      end

      ov.dig('hp_max', 'value')&.to_i || hp_max
    end
  end
end
