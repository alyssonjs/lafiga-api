# frozen_string_literal: true

# Aplica o ASI-as-feat selecionado num nivel especifico, fazendo a ponte entre
# `metadata.class_choices.per_level[N].asi` (o que o wizard/front gravou) e o
# `FeatAssignmentService` (que persiste em sheet_feats + metadata['feats']).
#
# Por que existe:
#   - `LevelUpService` so cria SheetKlass/HP/feature grants. Antes desta classe
#     ele simplesmente IGNORAVA `per_level[N].asi.featId` e o feat sumia.
#   - `CharacterSheetEdits::ProgressionEditService` so atualiza
#     `metadata.class_choices.per_level[N]`. Tambem ignorava `asi.featId`.
#
# Resultado do bug original (caso "Adimael Neverdie / Observador"):
#   - sheet_feats vazio.
#   - metadata['feats'] vazio.
#   - CharacterSheetSummaryService.build_abilities nao soma +1 SAB
#     (so trata mode in [attributes, plus2, plus1x2]; mode='feat' e ignorado
#     porque feat aparece via metadata['feats'], nao via per_level.asi).
#
# Esta classe e o ponto unico que cura ambos os caminhos.
#
# Idempotencia:
#   FeatAssignmentService ja trata re-aplicacao no mesmo level_gained
#   (destroy + recreate). Ver feat_assignment_service.rb:47-57.
class AsiFeatApplier
  Result = Struct.new(:applied, :skipped_reason, :sheet_feat, keyword_init: true)

  # @param sheet [Sheet]
  # @param level [Integer] nivel onde o ASI foi escolhido (1..20)
  # @return [Result]
  def self.call(sheet:, level:)
    new(sheet: sheet, level: level).call
  end

  def initialize(sheet:, level:)
    @sheet = sheet
    @level = level.to_i
  end

  def call
    asi = read_asi_row
    return Result.new(applied: false, skipped_reason: :no_per_level_row) if asi.nil?
    unless feat_mode?(asi)
      SheetFeatLevelCleaner.call(sheet: @sheet, levels: [@level])
      return Result.new(applied: false, skipped_reason: :not_feat_mode)
    end

    feat_id = (asi['featId'] || asi[:featId]).to_s
    if feat_id.empty?
      SheetFeatLevelCleaner.call(sheet: @sheet, levels: [@level])
      return Result.new(applied: false, skipped_reason: :missing_feat_id)
    end

    choices = build_choices(asi)
    cmd = FeatAssignmentService.call(
      sheet: @sheet,
      feat_id: feat_id,
      level_gained: @level,
      choices: choices
    )

    if cmd.respond_to?(:success?) && !cmd.success?
      Rails.logger.warn("AsiFeatApplier: FeatAssignmentService falhou para #{feat_id} no L#{@level}: #{cmd.errors.full_messages.inspect}")
      return Result.new(applied: false, skipped_reason: :assignment_failed)
    end

    sf = cmd.respond_to?(:result) ? cmd.result : cmd
    Result.new(applied: true, sheet_feat: sf)
  end

  private

  def read_asi_row
    meta = @sheet.metadata || {}
    row  = meta.dig('class_choices', 'per_level', @level.to_s)
    return nil unless row.is_a?(Hash)

    row['asi'] || row[:asi]
  end

  def feat_mode?(asi)
    return false unless asi.is_a?(Hash)

    (asi['mode'] || asi[:mode]).to_s == 'feat'
  end

  # Monta o `choices` que o `FeatAssignmentService` consome, espelhando o que
  # `LevelChoiceNormalizer.build_asi` produz a partir do front. Aceita tanto
  # rows ja normalizadas (caso comum: per_level no metadata) quanto rows
  # construidas em testes/admin sem passar pelo normalizer.
  def build_choices(asi)
    base = (asi['choices'] || asi[:choices]).is_a?(Hash) ? (asi['choices'] || asi[:choices]).deep_dup : {}
    base = base.deep_stringify_keys
    base['ability'] ||= (asi['featAbility'] || asi[:featAbility]).to_s if (asi['featAbility'] || asi[:featAbility]).present?
    base
  end
end
