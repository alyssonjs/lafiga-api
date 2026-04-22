module CharacterSheetEdits
  # Maps StepKey -> service class for surgical edit mode (status: 'active').
  REGISTRY = {
    'general'     => 'CharacterSheetEdits::GeneralEditService',
    'race'        => 'CharacterSheetEdits::RaceEditService',
    'background'  => 'CharacterSheetEdits::BackgroundEditService',
    'class'       => 'CharacterSheetEdits::ClassEditService',
    'abilities'   => 'CharacterSheetEdits::AbilitiesEditService',
    'skills'      => 'CharacterSheetEdits::SkillsEditService',
    'progression' => 'CharacterSheetEdits::ProgressionEditService',
    'equipment'   => 'CharacterSheetEdits::EquipmentEditService',
    'alignment'   => 'CharacterSheetEdits::AlignmentEditService',
    'avatar'      => 'CharacterSheetEdits::AvatarEditService',
    'review'      => 'CharacterSheetEdits::ReviewEditService'
  }.freeze

  def self.service_for(step_key)
    name = REGISTRY[step_key.to_s] or raise ArgumentError, "Unknown sheet edit step: #{step_key.inspect}"
    name.constantize
  end
end
