class BackgroundAssignmentService
  prepend SimpleCommand

  # Params:
  # - sheet: Sheet
  # - key: background key (slug)
  # - choices: { languages: [], gaming_set: [] }
  def initialize(sheet:, key:, choices: {})
    @sheet = sheet
    @key = key
    @choices = choices.is_a?(ActionController::Parameters) ? choices.to_unsafe_h : (choices || {})
  end

  def call
    summary = BackgroundRules.apply(key: @key, choices: @choices)
    data = (@sheet.metadata || {}).dup
    data['background_summary'] = summary
    @sheet.update!(metadata: data)
    summary
  rescue => e
    errors.add(:base, e.message)
    nil
  end
end

