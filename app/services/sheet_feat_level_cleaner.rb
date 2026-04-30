# frozen_string_literal: true

# Remove feats assigned at specific character levels from both DB and metadata.
# Used when an ASI level stops being "feat" mode and becomes a pure ability
# increase, so the previous SheetFeat does not keep affecting the sheet.
class SheetFeatLevelCleaner
  def self.call(sheet:, levels:)
    new(sheet: sheet, levels: levels).call
  end

  def initialize(sheet:, levels:)
    @sheet = sheet
    @levels = Array(levels).map(&:to_i).select(&:positive?).uniq
  end

  def call
    return if @sheet.nil? || @levels.empty?

    @sheet.sheet_feats.where(level_gained: @levels).destroy_all

    metadata = (@sheet.reload.metadata || {}).deep_stringify_keys
    feats = Array(metadata['feats']).reject do |entry|
      next false unless entry.is_a?(Hash)

      @levels.include?((entry['level_gained'] || entry[:level_gained]).to_i)
    end
    metadata['feats'] = feats
    @sheet.update!(metadata: metadata)
  end
end
