class SpellPreparationService
  prepend SimpleCommand

  def initialize(sheet:, klass_id:, spell_ids: [])
    @sheet = sheet
    @klass = Klass.find(klass_id)
    @spell_ids = Array(spell_ids).map(&:to_i)
  end

  def call
    limit = SpellRules.prepared_limit_for(@sheet, @klass)
    # Auto-prepared (always_prepared) entram por fora do limite
    auto_ids = SpellSource.where(source_type: 'Klass', source_id: @klass.id, always_prepared: true).pluck(:spell_id)
    raise StandardError, "Limite de magias preparadas excedido (#{limit})" if @spell_ids.size > limit

    # Limpa preparadas não-auto desta classe e regrava
    SheetPreparedSpell.where(sheet_id: @sheet.id, source: 'class', auto: false).delete_all
    @spell_ids.each do |sid|
      SheetPreparedSpell.create!(sheet_id: @sheet.id, spell_id: sid, auto: false, source: 'class')
    end

    # Garante auto-prepared
    auto_ids.each do |sid|
      SheetPreparedSpell.find_or_create_by!(sheet_id: @sheet.id, spell_id: sid) do |sp|
        sp.auto = true
        sp.source = 'class'
      end
    end
    true
  end
end

