module CharacterDraftSteps
  # Maps StepKey -> service class. Add new steps here.
  # Constants are referenced lazily so Zeitwerk autoloads each subclass on first use.
  REGISTRY = {
    'general'     => 'CharacterDraftSteps::GeneralStepService',
    'race'        => 'CharacterDraftSteps::RaceStepService',
    'background'  => 'CharacterDraftSteps::BackgroundStepService',
    'class'       => 'CharacterDraftSteps::ClassStepService',
    'abilities'   => 'CharacterDraftSteps::AbilitiesStepService',
    'skills'      => 'CharacterDraftSteps::SkillsStepService',
    'progression' => 'CharacterDraftSteps::ProgressionStepService',
    'equipment'   => 'CharacterDraftSteps::EquipmentStepService',
    'alignment'   => 'CharacterDraftSteps::AlignmentStepService',
    'avatar'      => 'CharacterDraftSteps::AvatarStepService',
    'review'      => 'CharacterDraftSteps::ReviewStepService'
  }.freeze

  def self.service_for(step_key)
    name = REGISTRY[step_key.to_s] or raise ArgumentError, "Unknown draft step: #{step_key.inspect}"
    name.constantize
  end
end
