module CharacterSheetEdits
  class AlignmentEditService < BaseSheetEditService
    def step_key = 'alignment'

    # Retorna o `alignmentIndex` (api_index/slug) ALÉM do DB id porque o catálogo
    # do front usa slugs como identidade (ex.: 'lawful-good' → wizard 'al-1').
    # Sem o slug, o front não consegue resolver o alignment a partir do id numérico
    # do banco e cai num estado "Alinhamento incompleto" no wizard de edição após
    # hard refresh (sem cache local). Mantemos `alignmentId` para compat retro com
    # `apply!` antigo (aceita id numérico).
    def read
      align = sheet.alignment_id ? Alignment.find_by(id: sheet.alignment_id) : nil
      {
        'alignmentId'    => sheet.alignment_id&.to_s,
        'alignmentIndex' => align&.api_index
      }
    end

    protected

    def apply!
      # ZE6 do segundo audit: a busca por slug usava `find_by(api_index: idx)`
      # literal, sem normalizar kebab/snake. Slugs como 'lawful_good' (snake)
      # do legacy seed nao casavam com 'lawful-good' (kebab) do front. Agora
      # passamos pelo helper compartilhado `resolve_polymorphic_id`, que aceita
      # ambos os formatos + id numerico, mantendo paridade com Race/Background.
      idx = data['alignmentIndex'].presence
      raw_id = data['alignmentId']

      align = nil
      if idx
        align_id = resolve_polymorphic_id(Alignment, idx)
        align = Alignment.find_by(id: align_id) if align_id
      end
      if align.nil? && raw_id.present?
        align_id = resolve_polymorphic_id(Alignment, raw_id)
        align = Alignment.find_by(id: align_id) if align_id
      end

      # `apply!` só toca o sheet quando o payload mencionou o alinhamento
      # (parity com o comportamento anterior: nada → no-op).
      return unless data.key?('alignmentId') || data.key?('alignmentIndex')

      sheet.alignment_id = align&.id
      meta = (sheet.metadata || {}).deep_stringify_keys
      meta['alignment'] = align ? { 'index' => align.api_index } : nil
      sheet.metadata = meta.compact
      sheet.save!
    end
  end
end
