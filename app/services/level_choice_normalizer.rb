# Translates the wizard's `levelChoice` row (front shape) into the canonical
# `per_level` row consumed by CharacterSheetSummaryService /
# CharacterProvisioningService (which expect `row['asi']` and
# `row['asi']['choices']`).
#
# Front-end shape (`asiChoice`):
#   {
#     mode: 'plus2' | 'plus1x2' | 'feat',
#     ability1?: 'str'..'cha',
#     ability2?: 'str'..'cha',
#     featId?: 'feat-xyz',
#     featAbility?: 'str'..'cha',
#     featGrantChoices?: { skills, tools, cantrips, spells, languages, ... }
#   }
#
# Backend shape (`asi`):
#   {
#     mode, ability1, ability2, featId, featAbility,
#     choices: { ability, proficiencies, cantrips, spells, ... }
#   }
#
# Used by:
#   - CharacterDraftPayloadBuilder#class_picks_by_level (creation/provision)
#   - CharacterSheetEdits::ProgressionEditService#apply!  (edit on active sheet)
#
# Idempotent: a row that already carries `asi` (legacy / re-saved) is left alone.
module LevelChoiceNormalizer
  module_function

  # Maps `featGrantChoices` keys to the keys FeatRules.apply expects.
  GRANT_KEY_RENAMES = {
    'skills' => 'proficiencies'
  }.freeze

  # Returns a new Hash (does not mutate the input).
  def normalize_row(row)
    return row unless row.is_a?(Hash)
    out = row.deep_stringify_keys

    asi_choice = out.delete('asiChoice')
    return out if asi_choice.blank?
    return out if out['asi'].is_a?(Hash) # already normalized

    out['asi'] = build_asi(asi_choice)
    out
  end

  # Inverso de `normalize_row`: converte uma `per_level` row canônica do backend
  # (com `asi`) para o shape do front (`asiChoice`). Usado pelo `read` dos
  # Edit/Draft services para que o wizard hidrate o `ASIChooser` corretamente
  # ao reabrir a edição — sem isso o ASI escolhido "sumia" do dropdown.
  GRANT_KEY_RENAMES_INV = GRANT_KEY_RENAMES.invert.freeze

  def denormalize_row(row)
    return row unless row.is_a?(Hash)
    out = row.deep_stringify_keys
    asi = out['asi']
    return out unless asi.is_a?(Hash)
    return out if out['asiChoice'].is_a?(Hash) # idempotente

    asi_choice = {}
    asi_choice['mode'] = asi['mode'] if asi['mode'].present?
    %w[ability1 ability2 featId featAbility].each do |k|
      asi_choice[k] = asi[k] if asi[k].present?
    end
    choices = asi['choices']
    if choices.is_a?(Hash) && choices.any?
      grants = {}
      choices.each do |k, v|
        # `ability` é redundante com `featAbility`; não rehidratar como grant.
        next if k.to_s == 'ability'
        grants[GRANT_KEY_RENAMES_INV[k.to_s] || k.to_s] = v
      end
      asi_choice['featGrantChoices'] = grants if grants.any?
    end
    out['asiChoice'] = asi_choice
    out
  end

  def build_asi(raw)
    src = raw.deep_stringify_keys
    asi = {}
    asi['mode'] = src['mode'].to_s if src['mode'].present?
    %w[ability1 ability2 featId featAbility].each do |k|
      v = src[k]
      asi[k] = v if v.present?
    end

    grants = src['featGrantChoices']
    if grants.is_a?(Hash) && grants.any?
      choices = {}
      grants.each do |k, v|
        choices[GRANT_KEY_RENAMES[k.to_s] || k.to_s] = v
      end
      # FeatRules.apply reads choices['ability'] for the +1 picker; mirror it
      # so feats with a chosen ability bonus actually get the score increment.
      choices['ability'] ||= asi['featAbility'] if asi['featAbility'].present?
      asi['choices'] = choices
    elsif asi['featAbility'].present?
      asi['choices'] = { 'ability' => asi['featAbility'] }
    end

    asi
  end
end
