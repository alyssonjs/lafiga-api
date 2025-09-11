class ClassProfileService
  def initialize(sheet)
    @sheet = sheet
    @sk = primary_sheet_klass
  end

  def call
    return {} unless @sk&.klass
    klass = @sk.klass
    ability = (klass.spellcasting_ability || 'CHA').to_s.upcase
    mods = ability_mods
    prof = CharacterRules.proficiency_bonus(CharacterRules.total_level(@sheet))
    mod = mods[ability.downcase.to_sym] || 0
    atk_bonus = mod + prof
    dc = 8 + mod + prof

    bard_like = klass.name.to_s.downcase.include?('bard') || klass.name.to_s.downcase.include?('bardo')
    inspiration_die = if @sk.level.to_i >= 15 then 'd12' elsif @sk.level.to_i >= 10 then 'd10' elsif @sk.level.to_i >= 5 then 'd8' else 'd6' end
    song_rest_die = if @sk.level.to_i >= 17 then 'd12' elsif @sk.level.to_i >= 13 then 'd10' elsif @sk.level.to_i >= 9 then 'd8' elsif @sk.level.to_i >= 2 then 'd6' else nil end

    cl = ClassLevel.includes(:spellcasting).find_by(klass_id: klass.id, level: @sk.level)
    slots = normalize_slots(cl&.spellcasting)

    meta_focus = (@sheet.metadata || {}).dig('class_summary', 'spellcasting', 'focus') || (@sheet.metadata || {}).dig('class_summary', 'focus')
    focus = meta_focus || (bard_like ? 'instrumento musical' : nil)

    {
      ability: ability,
      spell_attack_bonus: atk_bonus,
      spell_save_dc: dc,
      inspiration: (bard_like ? { die: inspiration_die, total: [1, (mods[:cha] || 0)].max, used: 0 } : nil),
      song_of_rest_die: (bard_like ? song_rest_die : nil),
      focus: focus,
      slots: slots
    }
  end

  private

  def primary_sheet_klass
    @sheet.sheet_klasses.max_by { |sk| sk.level.to_i }
  end

  def ability_mods
    sc = @sheet
    {
      str: CharacterRules.modifier(sc.str),
      dex: CharacterRules.modifier(sc.dex),
      con: CharacterRules.modifier(sc.con),
      int: CharacterRules.modifier(sc.int),
      wis: CharacterRules.modifier(sc.wis),
      cha: CharacterRules.modifier(sc.cha),
    }
  end

  def normalize_slots(spellcasting)
    arr = Array.new(9, 0)
    return arr unless spellcasting
    raw = spellcasting.spell_slots
    data = raw
    if raw.is_a?(String)
      begin
        data = JSON.parse(raw)
      rescue
        data = {}
      end
    end
    if data.is_a?(Array)
      (1..9).each { |i| arr[i-1] = (data[i] || data[i-1] || 0).to_i }
    elsif data.is_a?(Hash)
      (1..9).each do |i|
        v = data[i.to_s] || data["level_#{i}"] || data["l#{i}"] || data["lvl#{i}"]
        arr[i-1] = v.to_i
      end
    end
    arr
  end
end

