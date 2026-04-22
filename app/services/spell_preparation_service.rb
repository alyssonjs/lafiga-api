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
    klass_auto_ids = SpellSource.where(source_type: 'Klass', source_id: @klass.id, always_prepared: true).pluck(:spell_id)
    # Também incluir auto-prepared vindos da SubKlass selecionada, se houver
    subclass_auto_ids = begin
      sk = @sheet.sheet_klasses.includes(:sub_klass).find { |row| row.klass_id == @klass.id }
      if sk&.sub_klass_id
        SpellSource.where(source_type: 'SubKlass', source_id: sk.sub_klass_id, always_prepared: true).pluck(:spell_id)
      else
        []
      end
    rescue
      []
    end
    auto_ids = (klass_auto_ids + subclass_auto_ids).uniq
    raise StandardError, "Limite de magias preparadas excedido (#{limit})" if @spell_ids.size > limit

    # Wizard hardening (bulk): quando a única classe preparada for Mago,
    # todas as magias preparadas devem estar no grimório (SheetKnownSpell do Mago).
    begin
      if @klass.api_index == 'wizard'
        prepared_klasses = @sheet.sheet_klasses.includes(:klass).map(&:klass).select { |k| %w[cleric druid wizard paladin].include?(k.api_index) }
        prepared_keys = prepared_klasses.map(&:api_index).uniq
        if prepared_keys == ['wizard']
          wizard_sk = @sheet.sheet_klasses.includes(:klass).find { |sk| sk.klass_id == @klass.id }
          if wizard_sk
            unknown = @spell_ids.reject { |sid| SheetKnownSpell.exists?(sheet_klass_id: wizard_sk.id, spell_id: sid) }
            if unknown.any?
              raise StandardError, 'Mago: só pode preparar magias que estejam no grimório.'
            end
          end
        end
      end
    rescue => _e
      # Ignore soft errors here; other validations still apply
    end

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
