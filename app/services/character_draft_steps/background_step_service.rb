module CharacterDraftSteps
  class BackgroundStepService < BaseStepService
    def step_key = 'background'

    ARRAY_KEYS = %w[
      backgroundToolChoices backgroundLanguageChoices
      backgroundPersonalityTraits backgroundIdeals backgroundBonds backgroundFlaws
    ].freeze

    BACKGROUND_CHANGED_REASON =
      'Trocar de antecedente apaga as proficiencias em ferramentas/idiomas e os ' \
      'tracos de personalidade do antecedente anterior.'

    protected

    def apply!(merged)
      if data.key?('backgroundId')
        merged['_bgId'] = data['backgroundId']
        merged['_bgName'] = data['backgroundName']
        merged['selectedBackground'] = data['backgroundId'] ? { 'id' => data['backgroundId'], 'name' => data['backgroundName'] } : nil
      elsif data.key?('backgroundName')
        merged['_bgName'] = data['backgroundName']
      end
      ARRAY_KEYS.each { |k| merged[k] = Array(data[k]) if data.key?(k) }
    end

    # Gap G3.3 do relatorio de auditoria de steps: trocar de background
    # mantinha indevidamente:
    #   - backgroundToolChoices (proficiencias selecionadas do bg antigo)
    #   - backgroundLanguageChoices (idiomas selecionados do bg antigo)
    #   - backgroundPersonalityTraits/Ideals/Bonds/Flaws (tracos especificos)
    # Resultado: trocar Soldado -> Erudito mantinha "ferramentas de jogo" do
    # Soldado mesmo sem o Erudito conceder essa proficiencia, e o personagem
    # acabava com tracos misturados de dois backgrounds. Mesma logica de
    # ClassStepService/RaceStepService: so zera o que NAO veio no MESMO PATCH
    # (cliente que envia `{backgroundId, backgroundToolChoices, ...}` atomicamente
    # mantem suas escolhas).
    def invalidate!(prev, merged)
      prev_id = prev['_bgId'] || prev.dig('selectedBackground', 'id')
      new_id  = merged['_bgId'] || merged.dig('selectedBackground', 'id')
      return if prev_id.to_s == new_id.to_s

      destructive = prev_id.present? && new_id.present?

      ARRAY_KEYS.each do |k|
        next if data.key?(k)
        merged[k] = []
        clear!(k, reason: BACKGROUND_CHANGED_REASON, confirm: destructive)
      end
    end
  end
end
