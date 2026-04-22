module CharacterDraftSteps
  class RaceStepService < BaseStepService
    def step_key = 'race'

    protected

    def apply!(merged)
      if data.key?('raceId')
        merged['_raceId'] = data['raceId']
        merged['selectedRace'] = (data['raceId'] ? { 'id' => data['raceId'] } : nil)
      end
      if data.key?('subraceId')
        merged['selectedSubrace'] = data['subraceId'] ? { 'id' => data['subraceId'] } : nil
      end
      merged['raceChoices'] = data['raceChoices'] if data.key?('raceChoices')
      if data.key?('featId')
        merged['_featId'] = data['featId']
        merged['selectedFeat'] = data['featId'] ? { 'id' => data['featId'] } : nil
      end
      if data.key?('gender')
        # Gap G10.2 do relatorio de auditoria de steps: `gender` tem dois
        # owners semanticos (StepRace e StepAvatar) mas UMA SO chave
        # canonica: `avatarCustomization['gender']`. Em PATCHes paralelos
        # (race + avatar simultaneos), last-write-wins na MESMA chave —
        # comportamento aceitavel desde que ambos os caminhos escrevam
        # exatamente este key path. NUNCA armazenar gender em outro
        # campo (`merged['gender']`, `merged['_gender']`, etc.) sem
        # tambem mirror em `avatarCustomization['gender']`.
        merged['avatarCustomization'] ||= {}
        merged['avatarCustomization']['gender'] = normalize_gender(data['gender'])
      end
    end

    private

    # ZS7 do segundo audit: `gender` era persistido cru — clientes mandavam
    # 'masculino', 'M', 'male', 'Male', 'feminino', 'F', 'female' aleatoriamente.
    # O backend tratava cada string distinta como valor unico, quebrando
    # comparacoes (`gender == 'male'`) downstream e atrapalhando a selecao de
    # avatares hero por genero. Normalizamos para o conjunto canonico do front
    # (chibi/hero asset registry usa 'male'/'female'/'nonbinary').
    GENDER_MAP = {
      'masculino' => 'male', 'masc' => 'male', 'm' => 'male', 'male' => 'male', 'homem' => 'male',
      'feminino' => 'female', 'fem' => 'female', 'f' => 'female', 'female' => 'female', 'mulher' => 'female',
      'nao-binario' => 'nonbinary', 'naobinario' => 'nonbinary', 'nb' => 'nonbinary',
      'nao binario' => 'nonbinary', 'nonbinary' => 'nonbinary', 'non-binary' => 'nonbinary'
    }.freeze

    def normalize_gender(raw)
      return nil if raw.nil?
      key = raw.to_s.strip.downcase
      GENDER_MAP[key] || key
    end

    def invalidate!(prev, merged)
      prev_id = prev.dig('selectedRace', 'id') || prev['_raceId']
      new_id  = merged.dig('selectedRace', 'id') || merged['_raceId']
      return if prev_id.to_s == new_id.to_s
      # Setting race for the first time is NOT a destructive change and must
      # not wipe raceChoices submitted in the same call.
      return if prev_id.blank?

      destructive = new_id.present?

      # Preserve raceChoices/subrace/feat that were SET in this same call
      # (the user replaced race + new choices atomically).
      merged['raceChoices'] = {} unless data.key?('raceChoices')
      merged['selectedSubrace'] = nil unless data.key?('subraceId')
      unless data.key?('featId')
        merged['selectedFeat'] = nil
        merged['_featId'] = nil
      end

      # Gap G2.4 do relatorio de auditoria de steps: `clear!` era chamado
      # incondicionalmente para `raceChoices`, `selectedSubrace` e
      # `selectedFeat`, gerando `requires_confirmation` mesmo quando o
      # player vinha de uma raca que NAO tinha esses campos populados
      # (ex.: trocar Anão -> Halfling sem nunca ter escolhido feat).
      # Resultado: UI mostrava "voce vai perder selectedFeat" para um
      # campo que nunca existiu. Agora so reportamos cleanup quando
      # havia conteudo real a perder (parity com BackgroundEditService
      # G3.3 que so dispara `cleared_any` quando `bc[k].present?`).
      had_choices = prev['raceChoices'].is_a?(Hash) && prev['raceChoices'].any?
      had_subrace = prev['selectedSubrace'].present? || prev['_subRaceId'].present?
      had_feat    = prev['_featId'].present? || prev['selectedFeat'].present?

      clear!('raceChoices')                                                                if had_choices
      clear!('selectedSubrace')                                                            if had_subrace
      clear!('selectedFeat', reason: DESTRUCTIVE_REASONS[:race_changed], confirm: destructive) if had_feat
    end
  end
end
