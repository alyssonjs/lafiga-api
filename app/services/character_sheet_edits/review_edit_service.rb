module CharacterSheetEdits
  # No-op: review step has nothing to apply on an active sheet.
  class ReviewEditService < BaseSheetEditService
    def step_key = 'review'

    def read = {}

    protected

    def apply!
      # nothing to do
    end
  end
end
