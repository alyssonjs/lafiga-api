module CharacterSheetEdits
  # No-op: review step has nothing to apply on an active sheet.
  class ReviewEditService < BaseSheetEditService
    def step_key = 'review'

    def read = {}

    protected

    def apply!
      # Rever/Publicar no fim do wizard de edição: sincroniza PV com per_level + racial.
      # Assim quem só altera passos gerais e grava em "Revisão" corrige hp_max obsoleto.
      sk = sheet.sheet_klasses.order(level: :desc).first
      return unless sk&.klass

      apply_progression_hp_to_sheet!
      sheet.save! if sheet.changed?
    end
  end
end
