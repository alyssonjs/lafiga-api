require 'set'
# frozen_string_literal: true

module Sheets
  # Proficiências que o MESTRE concedeu a este personagem, fora da regra.
  #
  # Irmã de `Sheets::Training` na forma (mapa indexado por
  # `proficiency.api_index`, com a marca de quem e quando), e deliberadamente
  # SEPARADA dela: uma diz "o personagem treinou e concluiu", a outra diz "o
  # Mestre deu". Misturá-las faria a ficha perder a diferença, que é justamente
  # o que o mestre quer ver.
  #
  # O mesmo mapa guarda as DUAS direções — conceder e retirar:
  #
  #   sheet.dm_proficiencies = {
  #     'skill-furtividade' => {                      # concedida
  #       'note' => 'aprendeu com o mestre ladrão de Vorthek',
  #       'by_user_id' => 3, 'at' => '2026-09-11T...'
  #     },
  #     'skill-atletismo' => {                        # RETIRADA
  #       'revoked' => true, 'note' => 'perdeu o braço em Vorthek'
  #     }
  #   }
  #
  # ⚠️ Retirar é o espelho de conceder, e por isso mora aqui e não noutro sítio:
  # as duas são a mesma decisão do mestre sobre a mesma proficiência, e separá-las
  # deixaria a ficha sem saber qual venceu se ambas existissem.
  #
  # A revogação tira a proficiência de QUALQUER fonte — classe, raça,
  # antecedente, treino. É o ponto: o mestre está a passar por cima da regra.
  module DmProficiencies
    module_function

    # Normaliza o patch. Devolve `[hash_limpo, erros]`.
    #
    # ⚠️ A chave TEM de existir no catálogo. Sem isso um erro de digitação
    # concederia uma proficiência que ninguém tem e que não apareceria em lado
    # nenhum — o modo de falha silencioso de sempre.
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

        # `nil` é o gesto de RETIRAR a concessão.
        if entry.nil?
          out[k] = nil
          next
        end

        h = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
        h = h.is_a?(Hash) ? h.transform_keys(&:to_s) : {}
        anterior = (previous || {})[k] || {}

        linha = anterior.dup
        # Campo ausente não mexe no que já estava — patch parcial, como no irmão.
        linha['note'] = h['note'].presence&.to_s&.slice(0, 240) if h.key?('note')
        if h.key?('revoked')
          ActiveModel::Type::Boolean.new.cast(h['revoked']) ? linha['revoked'] = true : linha.delete('revoked')
        end
        linha['by_user_id'] = actor_id || anterior['by_user_id']
        linha['at'] = anterior['at'] || Time.current.iso8601
        out[k] = linha.compact
      end
      [out, erros]
    end

    def merge(current, patch)
      base = (current || {}).dup
      (patch || {}).each { |k, v| v.nil? ? base.delete(k) : base[k] = v }
      base
    end

    # A lista que a ficha mostra, com nome, categoria e direção.
    def list(dm_proficiencies)
      (dm_proficiencies || {}).filter_map do |chave, linha|
        prof = Proficiency.find_by(api_index: chave.to_s)
        next if prof.nil?

        h = linha.is_a?(Hash) ? linha : {}
        {
          'api_index' => chave.to_s,
          'name' => prof.name,
          'category' => prof.category,
          'revoked' => h['revoked'] == true,
          'note' => h['note'],
          'at' => h['at']
        }.compact
      end.sort_by { |l| [l['revoked'] ? 1 : 0, l['name'].to_s] }
    rescue StandardError
      # Catálogo ausente não derruba a ficha inteira.
      []
    end

    # As CONCEDIDAS, por categoria — é assim que entram na lista.
    def by_category(dm_proficiencies)
      list(dm_proficiencies).reject { |l| l['revoked'] }
                            .each_with_object(Hash.new { |h, k| h[k] = [] }) do |linha, acc|
        acc[linha['category'].to_s] << linha['name']
      end
    end

    # As RETIRADAS, em forma normalizada — a lista da ficha são STRINGS, e o
    # nome pode chegar com outra grafia ("Élfico" vs "elfico").
    def revoked_keys(dm_proficiencies)
      list(dm_proficiencies).select { |l| l['revoked'] }
                            .map { |l| Proficiency.normalize(l['name']) }
                            .to_set
    rescue StandardError
      Set.new
    end
  end
end
