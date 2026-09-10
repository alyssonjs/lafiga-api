# frozen_string_literal: true

module Sheets
  # Horas de treino cravadas pelo MESTRE para UM personagem.
  #
  # O catálogo diz o padrão; isto é a exceção, caso a caso. Irmão de
  # `Sheets::DmOverrides` no formato da marca (valor + padrão + motivo + quem +
  # quando), mas serviço à parte porque a forma do dado é outra: aquilo é uma
  # lista branca de números soltos, isto é um mapa indexado por
  # `proficiency.api_index`.
  #
  #   sheet.training_overrides = {
  #     'tool-ferramentas-de-ferreiro' => {
  #       'hours' => 80, 'default' => 120,
  #       'note' => 'cresceu na forja do pai', 'by_user_id' => 3, 'at' => '...'
  #     }
  #   }
  module TrainingOverrides
    # Teto largo de propósito: é o mestre a decidir, e a regra existe só para
    # apanhar engano de digitação (o "8000" que era "80").
    MAX_HOURS = 100_000

    module_function

    # Normaliza o que veio do controller. Devolve `[hash_limpo, erros]`.
    #
    # ⚠️ A chave tem de existir no CATÁLOGO. Sem isso, um erro de digitação
    # gravaria horas para uma proficiência que ninguém tem, e o ajuste ficaria
    # invisível para sempre — o modo de falha silencioso de sempre neste
    # projeto.
    def sanitize(raw, actor_id: nil, previous: {})
      erros = []
      out = {}
      (raw || {}).each do |key, entry|
        k = key.to_s
        prof = Proficiency.find_by(api_index: k)
        if prof.nil?
          erros << "Proficiência não catalogada: #{k}"
          next
        end

        # `nil` é o gesto de REMOVER — solta, e volta a valer o padrão do catálogo.
        if entry.nil?
          out[k] = nil
          next
        end

        h = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
        h = h.is_a?(Hash) ? h.transform_keys(&:to_s) : { 'hours' => h }
        horas = clamp(h['hours'])
        if horas.nil?
          erros << "Horas inválidas para #{k}: #{h['hours'].inspect}"
          next
        end

        anterior = (previous || {})[k]
        out[k] = {
          'hours' => horas,
          # O padrão do catálogo NO MOMENTO em que o mestre cravou. É o que
          # deixa a ficha dizer "o catálogo pede 120, o Mestre pôs 80" — e
          # continuar a dizê-lo mesmo que o catálogo mude depois.
          'default' => prof.training_hours || anterior&.dig('default'),
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

    def clamp(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      n = Integer(raw.to_s.strip, exception: false)
      return nil if n.nil? || n <= 0

      [n, MAX_HOURS].min
    end

    # Quantas horas ESTE personagem precisa para esta proficiência.
    #
    # Sobrescrita vence o catálogo; sem nenhuma das duas, `nil` — que significa
    # "ainda por definir", e não "de graça".
    def hours_for(overrides, proficiency)
      return nil if proficiency.nil?

      cravado = (overrides || {}).dig(proficiency.api_index, 'hours')
      cravado&.to_i || proficiency.training_hours
    end

    # O bloco que a ficha mostra, por proficiência treinável.
    def describe(overrides, proficiency)
      return nil unless proficiency&.trainable?

      ov = (overrides || {})[proficiency.api_index]
      {
        'api_index' => proficiency.api_index,
        'name' => proficiency.name,
        'hours' => hours_for(overrides, proficiency),
        'catalog_hours' => proficiency.training_hours,
        'overridden' => !ov.nil?,
        'note' => ov && ov['note'],
        'at' => ov && ov['at']
      }.compact
    end
  end
end
