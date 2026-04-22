module CharacterDraftSteps
  # No-op step. Provisioning is triggered via POST /character_drafts/:id/provision.
  class ReviewStepService < BaseStepService
    def step_key = 'review'

    protected

    def apply!(_merged)
      # nothing to merge — review is read-only.
    end
  end
end
