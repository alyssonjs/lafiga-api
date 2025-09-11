class SpellRules
  # Helpers para regras de magia. Métodos puros ou que consultam somente models.

  # Retorna hash { level(int) => slots(int) } somando classes conjuradoras padrão
  def self.standard_slot_table(sheet)
    # Aproximação: pegar maior tabela de slots entre classes com spellcasting e mesclar por nível
    result = Hash.new(0)
    sheet.sheet_klasses.includes(klass: { class_levels: :spellcasting }).each do |sk|
      sc = sc_for(sk.klass, sk.level)
      next unless sc
      slots = parse_slots(sc.spell_slots)
      slots.each { |lvl, qty| result[lvl] = [result[lvl], qty].max }
    end
    result
  end

  # Pact magic (Warlock) agregado: { pact_slot_level: int, slots: int }
  def self.pact_magic(sheet)
    pact_level = 0
    pact_slots = 0
    sheet.sheet_klasses.includes(klass: { class_levels: :spellcasting }).each do |sk|
      sc = sc_for(sk.klass, sk.level)
      next unless sc && sc.pact_slot_level.present?
      pact_level = [pact_level, sc.pact_slot_level.to_i].max
      slots = parse_slots(sc.pact_slots)
      pact_slots = [pact_slots, slots['pact'].to_i].max
    end
    { level: pact_level, slots: pact_slots }
  end

  def self.highest_standard_slot_level(sheet)
    standard_slot_table(sheet).keys.map(&:to_i).max || 0
  end

  def self.prepared_limit_for(sheet, klass)
    # Ex.: Cleric/Druid/Wizard: ability mod + class level. Outras classes variam.
    ability = klass.spellcasting_ability&.downcase
    return 0 unless ability
    ability_score = sheet.send(ability)
    sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
    return 0 unless sk
    base = case klass.api_index
           when 'paladin'
             # Paladin: CHA mod + metade do nível (arredondado para baixo)
             (sk.level.to_i / 2)
           else
             # Cleric/Druid/Wizard: habilidade + nível da classe
             sk.level.to_i
           end
    [1, (modifier(ability_score) + base)].max
  end

  def self.can_learn_spell?(sheet_klass, spell)
    sheet = sheet_klass.sheet
    klass = sheet_klass.klass
    spell_level = spell.level.to_i
    return true if spell_level.zero? # cantrips sempre permitidos

    # Warlock usa pact magic; demais usam slots padrão
    if klass.api_index == 'warlock' || klass.name.to_s.downcase.include?('bruxo')
      pact = pact_magic(sheet)
      return spell_level <= pact[:level].to_i
    end

    spell_level <= highest_standard_slot_level(sheet)
  end

  def self.modifier(score)
    return 0 if score.nil?
    ((score.to_i - 10) / 2.0).floor
  end

  def self.sc_for(klass, level)
    class_level = klass.class_levels.find_by(level: level)
    Rails.logger.info "ClassLevel.find_by(klass_id: #{klass.id}, level: #{level}) = #{class_level.present? ? 'found' : 'not found'}"
    class_level&.spellcasting
  end

  # Returns hash with :known_spells and :known_cantrips limits for a given SheetKlass
  def self.known_limits_for(sheet_klass)
    klass = sheet_klass.klass
    sc = sc_for(klass, sheet_klass.level)
    return { spells: nil, cantrips: nil } unless sc
    { spells: sc.spells_known, cantrips: sc.cantrips_known }
  end

  # Returns current counts of known spells (level > 0) and cantrips (level == 0) for a given SheetKlass
  def self.known_counts_for(sheet_klass)
    scope = SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).joins(:spell)
    spells = scope.where('spells.level > 0').count
    cantrips = scope.where('spells.level = 0').count
    { spells: spells, cantrips: cantrips }
  end

  def self.parse_slots(slots)
    case slots
    when String
      JSON.parse(slots) rescue {}
    when Hash
      slots
    else
      {}
    end
  end
end
