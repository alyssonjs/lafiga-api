class SpellRules
  # Helpers para regras de magia. Métodos puros ou que consultam somente models.

  # Retorna hash { level(int) => slots(int) } somando classes conjuradoras padrão
  def self.standard_slot_table(sheet)
    # Mescla slots padrão de classes e, quando não houver, slots de progressões por subclasse (override YAML)
    result = Hash.new(0)
    sheet.sheet_klasses.includes(:sub_klass, klass: { class_levels: :spellcasting }).each do |sk|
      sc = sc_for(sk.klass, sk.level)
      if sc
        slots = parse_slots(sc.spell_slots)
        slots.each { |lvl, qty| result[lvl] = [result[lvl], qty].max }
      else
        entry = subclass_sc_for(sk)
        if entry&.slots
          entry.slots.each { |lvl, qty| result[lvl.to_s] = [result[lvl.to_s], qty.to_i].max }
        end
      end
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

  # Fast path optionally accepts gate_level (max spell level allowed for this klass on this sheet)
  def self.can_learn_spell?(sheet_klass, spell, gate_level: nil)
    sheet = sheet_klass.sheet
    klass = sheet_klass.klass
    spell_level = spell.level.to_i
    return true if spell_level.zero? # cantrips sempre permitidos

    max_gate = gate_level || gate_for(sheet, klass)
    spell_level <= max_gate
  end

  def self.modifier(score)
    return 0 if score.nil?
    ((score.to_i - 10) / 2.0).floor
  end

  def self.sc_for(klass, level)
    class_level = if klass.class_levels.loaded?
                    # Use in-memory match when association is preloaded to avoid extra queries/logs
                    klass.class_levels.find { |cl| cl.level.to_i == level.to_i }
                  else
                    klass.class_levels.find_by(level: level)
                  end
    class_level&.spellcasting
  end

  # Retorna o nível máximo de magia permitida para esta classe nesta ficha.
  # - Warlock: nível do pact slot
  # - Demais: maior nível de slot padrão disponível
  #
  # Fallback PHB quando `spellcasting.spell_slots` / `pact_slot_level` não
  # estão populados no DB (seeder mínimo, import antigo): sem isso o gate vira
  # 0, `persist_known_spells!` não acha candidatos e o LevelUpGuard trava.
  def self.gate_for(sheet, klass)
    if klass.api_index == 'warlock' || klass.name.to_s.downcase.include?('bruxo')
      lvl = pact_magic(sheet)[:level].to_i
      return lvl if lvl.positive?

      sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
      return 1 unless sk

      # PHB: nível do slot de pacto por nível da classe (quando DB não tem pact_slot_level).
      pm = ClassRules::CLASS_RULES[:warlock]&.dig(:feature_rules, :pact_magic, :slot_level_by_level)
      if pm.is_a?(Hash)
        gl = (pm[sk.level] || pm[sk.level.to_s] || pm[sk.level.to_i]).to_i
        return gl.clamp(1, 9) if gl.positive?
      end

      1
    end

    std = highest_standard_slot_level(sheet).to_i
    return std if std.positive?

    sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
    return 0 unless sk

    lvl = sk.level.to_i
    idx = klass.api_index.to_s

    # Meio-conjurador PHB: maior círculo ≈ floor(nível/2), teto 5º (sem slots no DB).
    if %w[ranger paladin].include?(idx)
      return [lvl / 2, 5].min
    end

    # Conjurador integral: maior círculo ≈ ceil(nível/2) == (lvl+1)/2 em inteiros.
    if %w[bard cleric druid sorcerer wizard].include?(idx)
      return [[(lvl + 1) / 2, 9].min, 1].max
    end

    0
  end

  # Returns hash with :known_spells and :known_cantrips limits for a given SheetKlass
  def self.known_limits_for(sheet_klass)
    klass = sheet_klass.klass
    sc = sc_for(klass, sheet_klass.level)
    if sc
      return { spells: sc.spells_known, cantrips: sc.cantrips_known }
    end
    entry = subclass_sc_for(sheet_klass)
    return { spells: nil, cantrips: nil } unless entry
    { spells: entry.spells_known, cantrips: entry.cantrips_known }
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

  # Subclasse: retorna Entry (SubclassSpellcasting) para este SheetKlass (ou nil)
  def self.subclass_sc_for(sheet_klass)
    sub = sheet_klass.sub_klass
    return nil unless sub && sub.api_index.present?
    SubclassSpellcasting.lookup(
      klass_api: sheet_klass.klass.api_index,
      subclass_api: sub.api_index,
      level: sheet_klass.level
    )
  end
end
