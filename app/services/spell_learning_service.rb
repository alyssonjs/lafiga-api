class SpellLearningService
  prepend SimpleCommand

  def initialize(sheet_klass:, spell_id:)
    @sheet_klass = sheet_klass
    @spell = Spell.find(spell_id)
  end

  def call
    validate_sources!
    validate_level_cap!
    validate_known_limits!
    SheetKnownSpell.create!(sheet_klass: @sheet_klass, spell: @spell, gained_at_class_level: @sheet_klass.level, source: 'class')
  end

  private

  def validate_sources!
    # Deve existir fonte para a classe OU para a subclasse (expanded) OU regra de learn_any_class
    exists = SpellSource.exists?(source_type: 'Klass', source_id: @sheet_klass.klass_id, spell_id: @spell.id)
    return true if exists

    # expanded spells (warlock patrons, etc.)
    if @sheet_klass.sub_klass_id.present?
      expanded = SpellSource.exists?(source_type: 'SubKlass', source_id: @sheet_klass.sub_klass_id, spell_id: @spell.id)
      return true if expanded
    end

    # learn_any_class from subclass grants at current or lower level (best-effort, relies on metadata)
    begin
      meta = @sheet_klass.sheet.metadata || {}
      per = (meta.dig('class_choices','per_level') || {})
      # Detect marker set by FE/BE when allowing any-class learning
      any_flags = []
      (1..@sheet_klass.level.to_i).each do |lvl|
        row = per[lvl.to_s] || per[lvl] || {}
        any_flags << true if row['learn_any_class'] || row[:learn_any_class]
      end
      return true if any_flags.any?
    rescue
    end

    raise StandardError, 'Spell não pertence à lista da classe'
  end

  def validate_level_cap!
    allowed = SpellRules.can_learn_spell?(@sheet_klass, @spell)
    raise StandardError, 'Nível de magia acima do slot disponível' unless allowed
  end

  def validate_known_limits!
    limits = SpellRules.known_limits_for(@sheet_klass)
    counts = SpellRules.known_counts_for(@sheet_klass)
    if @spell.level.to_i == 0
      if limits[:cantrips] && counts[:cantrips].to_i >= limits[:cantrips].to_i
        raise StandardError, "Limite de truques (cantrips) alcançado (#{counts[:cantrips]}/#{limits[:cantrips]})"
      end
    else
      if limits[:spells] && counts[:spells].to_i >= limits[:spells].to_i
        raise StandardError, "Limite de magias conhecidas alcançado (#{counts[:spells]}/#{limits[:spells]})"
      end
    end
  end
end
