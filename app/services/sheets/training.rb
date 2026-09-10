# frozen_string_literal: true

module Sheets
  # Treino de proficiência de UM personagem: quantas horas ele precisa e
  # quantas já fez.
  #
  # Duas camadas, e é o mestre quem manda nas duas:
  #
  #   - o CATÁLOGO diz o padrão (`proficiencies.metadata.training_hours`);
  #   - a FICHA diz a exceção deste personagem (`hours_required`) e o progresso
  #     dele (`hours_trained`) — que o mestre conta à mão, sessão a sessão.
  #
  # Irmão de `Sheets::DmOverrides` no formato da marca (valor + padrão + motivo
  # + quem + quando), mas serviço à parte porque a forma do dado é outra:
  # aquilo é uma lista branca de números soltos, isto é um mapa indexado por
  # `proficiency.api_index`.
  #
  #   sheet.training = {
  #     'tool-lira' => {
  #       'hours_required' => 25,   # exceção; ausente = vale o catálogo
  #       'hours_trained'  => 12,   # o mestre conta
  #       'default' => 60,          # o padrão do catálogo quando cravou
  #       'note' => 'tocava desde criança', 'by_user_id' => 3, 'at' => '...'
  #     }
  #   }
  module Training
    # Teto largo de propósito: é o mestre a decidir, e a regra existe só para
    # apanhar engano de digitação (o "8000" que era "80").
    MAX_HOURS = 100_000
    CAMPOS = %w[hours_required hours_trained].freeze

    # ⚠️ `learning: true` marca a linha como APRENDIZADO — proficiência que o
    # personagem ainda NÃO tem e está a treinar, acrescentada pelo mestre no
    # card "Aprendizado".
    #
    # Podia-se derivar isto ("está a aprender o que ainda não tem"), mas a
    # marca explícita é o que deixa a linha CONTINUAR na lista depois de
    # concluída, com a etiqueta. Derivada, ela sumiria do card no instante em
    # que entrasse na lista de perícias — e o jogador não veria que a
    # concluiu.
    MARCA_APRENDIZADO = 'learning'

    module_function

    # Normaliza o que veio do controller. Devolve `[hash_limpo, erros]`.
    #
    # ⚠️ A chave tem de existir no CATÁLOGO. Sem isso, um erro de digitação
    # gravaria treino para uma proficiência que ninguém tem, e ficaria
    # invisível para sempre — o modo de falha silencioso de sempre.
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

        # `nil` é o gesto de APAGAR a linha inteira — solta a exceção E o
        # progresso, e a proficiência volta a valer só o padrão do catálogo.
        if entry.nil?
          out[k] = nil
          next
        end

        h = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry
        h = h.is_a?(Hash) ? h.transform_keys(&:to_s) : { 'hours_trained' => h }
        anterior = (previous || {})[k] || {}

        linha = anterior.dup
        CAMPOS.each do |campo|
          # Campo AUSENTE não mexe no que já estava — é patch parcial também
          # dentro da linha. Mandar só `hours_trained` não pode apagar a exceção
          # de horas que o mestre cravou noutro dia.
          next unless h.key?(campo)

          bruto = h[campo]
          # String vazia / nil = soltar SÓ este campo.
          if bruto.nil? || bruto.to_s.strip.empty?
            linha.delete(campo)
            next
          end

          valor = clamp(bruto)
          if valor.nil?
            erros << "#{campo} inválido para #{k}: #{bruto.inspect}"
            next
          end
          linha[campo] = valor
        end

        # O padrão do catálogo NO MOMENTO em que o mestre mexeu. É o que deixa a
        # ficha dizer "o catálogo pede 120, o Mestre pôs 80" mesmo que o
        # catálogo mude depois.
        # A marca de aprendizado é booleana e ausente = não mexe.
        if h.key?(MARCA_APRENDIZADO)
          bruto = h[MARCA_APRENDIZADO]
          if bruto.nil? || bruto.to_s.strip.empty?
            linha.delete(MARCA_APRENDIZADO)
          else
            ligado = ActiveModel::Type::Boolean.new.cast(bruto)
            ligado ? linha[MARCA_APRENDIZADO] = true : linha.delete(MARCA_APRENDIZADO)
          end
        end

        linha['default'] = prof.training_hours || anterior['default']
        linha['note'] = h['note'].presence&.to_s&.slice(0, 240) if h.key?('note')
        linha['by_user_id'] = actor_id || anterior['by_user_id']
        linha['at'] = Time.current.iso8601
        out[k] = linha.compact
      end
      [out, erros]
    end

    # Funde o patch no que já existe; chave com `nil` remove a linha.
    def merge(current, patch)
      base = (current || {}).dup
      (patch || {}).each { |k, v| v.nil? ? base.delete(k) : base[k] = v }
      base
    end

    def clamp(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      n = Integer(raw.to_s.strip, exception: false)
      return nil if n.nil? || n.negative?

      [n, MAX_HOURS].min
    end

    # Quantas horas ESTE personagem precisa. Exceção vence catálogo; sem
    # nenhuma das duas, `nil` — que é "ainda por definir", não "de graça".
    def hours_required(training, proficiency)
      return nil if proficiency.nil?

      (training || {}).dig(proficiency.api_index, 'hours_required')&.to_i ||
        proficiency.training_hours
    end

    # Quantas ele já fez. O mestre conta.
    def hours_trained(training, proficiency)
      return 0 if proficiency.nil?

      (training || {}).dig(proficiency.api_index, 'hours_trained').to_i
    end

    # ── APRENDIZADO ───────────────────────────────────────────────────────
    #
    # As linhas que o mestre marcou como aprendizado, com o progresso. É o que
    # alimenta o card "Aprendizado" no hub e na ficha.
    #
    # ⚠️ NÃO exige `proficiency.trainable?`. Medido: o catálogo tem 142 linhas e
    # ZERO marcadas como treináveis — exigir a marca faria o card nascer morto.
    # O gesto do mestre de acrescentar ao aprendizado É a declaração de que
    # aquilo se treina, que foi o que ele pediu desde o início ("o mestre define
    # a quantidade de horas caso a caso").
    def learning_list(training)
      linhas = (training || {}).filter_map do |chave, linha|
        next unless linha.is_a?(Hash) && linha[MARCA_APRENDIZADO]

        prof = Proficiency.find_by(api_index: chave.to_s)
        next if prof.nil?

        descreve_aprendizado(chave.to_s, linha, prof)
      end
      # Em curso primeiro (é o que o mestre vai mexer), depois por nome.
      linhas.sort_by { |l| [l['complete'] ? 1 : 0, l['name'].to_s] }
    rescue StandardError
      # Catálogo ausente não pode derrubar a ficha inteira.
      []
    end

    # As CONCLUÍDAS, agrupadas por categoria — é o que entra na lista de
    # proficiências do personagem, marcada como aprendida.
    def completed_by_category(training)
      learning_list(training).each_with_object(Hash.new { |h, k| h[k] = [] }) do |linha, acc|
        next unless linha['complete']

        acc[linha['category'].to_s] << linha['name']
      end
    end

    def descreve_aprendizado(chave, linha, prof)
      necessarias = linha['hours_required']&.to_i || prof.training_hours
      feitas = linha['hours_trained'].to_i

      {
        'api_index' => chave,
        'name' => prof.name,
        'category' => prof.category,
        'hours_required' => necessarias,
        'hours_trained' => feitas,
        # ⚠️ Sem horas definidas NÃO é completa. "Por definir" não pode virar
        # "já aprendeu" por omissão — seria dar a proficiência de graça.
        'complete' => necessarias.to_i.positive? && feitas >= necessarias.to_i,
        'remaining' => necessarias.to_i.positive? ? [necessarias.to_i - feitas, 0].max : nil,
        # A barra do card. Sem horas definidas não há barra que faça sentido.
        'percent' => necessarias.to_i.positive? ? [(feitas * 100.0 / necessarias).round, 100].min : nil,
        'note' => linha['note'],
        'at' => linha['at']
      }.compact
    end

    # O bloco que a ficha mostra, por proficiência treinável.
    def describe(training, proficiency)
      return nil unless proficiency&.trainable?

      linha = (training || {})[proficiency.api_index]
      necessarias = hours_required(training, proficiency)
      feitas = hours_trained(training, proficiency)

      {
        'api_index' => proficiency.api_index,
        'name' => proficiency.name,
        'hours_required' => necessarias,
        'hours_trained' => feitas,
        # ⚠️ `nil` quando não há horas definidas — e NÃO `true`. "Por definir"
        # não pode virar "já sabe" por omissão.
        'complete' => necessarias.nil? ? nil : feitas >= necessarias,
        'remaining' => necessarias.nil? ? nil : [necessarias - feitas, 0].max,
        'catalog_hours' => proficiency.training_hours,
        'overridden' => !linha.nil? && linha.key?('hours_required'),
        'note' => linha && linha['note'],
        'at' => linha && linha['at']
      }.compact
    end
  end
end
