class CharacterSheetSummaryService
  prepend SimpleCommand

  def initialize(sheet_id:, sync: true)
    @sheet = Sheet.includes(:character, :race, :sub_race, sheet_klasses: [:klass, :sub_klass]).find(sheet_id)
    @sync = sync
  end

  def call
    ActiveRecord::Base.transaction do
      sync_characters_features! if @sync

      total_level = CharacterRules.total_level(@sheet)
      prof = CharacterRules.proficiency_bonus(total_level)

      abilities = build_abilities(@sheet)
      movement  = RaceProfileService.new(@sheet).call.slice(:speed_ft, :speed_m)
      klasses   = build_klasses(@sheet)

      conj = ClassProfileService.new(@sheet).call
      features = FeaturesAggregator.new(@sheet, sync: @sync).call
      spells = KnownSpellsAggregator.new(@sheet).call
      equipment = EquipmentProfileService.new(@sheet).call rescue { inventory: [], equipped: {}, ac: { ac: (10 + CharacterRules.modifier(@sheet.dex)), source: 'Sem armadura' } }

      {
        sheet: {
          id: @sheet.id,
          character_id: @sheet.character_id,
          name: @sheet.character&.name,
          race: {
            id: @sheet.race_id,
            name: @sheet.race&.name,
            sub_race: (@sheet.sub_race ? { id: @sheet.sub_race_id, name: @sheet.sub_race&.name } : nil)
          }
        },
        abilities: abilities,
        movement: movement,
        prof_bonus: prof,
        klasses: klasses,
        proficiencies: build_proficiencies(@sheet),
        traits: build_traits(@sheet),
        background: build_background(@sheet),
        feats: build_feats(@sheet),
        conjuration: conj,
        features: features,
        features_catalog: build_feature_catalog,
        spells: spells,
        equipment: equipment
      }
    end
  rescue => e
    errors.add(:base, e.message)
    nil
  end

  private

  def build_abilities(sheet)
    scores = {
      str: sheet.str, dex: sheet.dex, con: sheet.con,
      int: sheet.int, wis: sheet.wis, cha: sheet.cha
    }
    mods = scores.transform_values { |v| CharacterRules.modifier(v) }
    { scores: scores, mods: mods }
  end

  def build_movement(sheet)
    meta = sheet.metadata || {}
    rs = meta['race_summary'] || {}
    {
      speed_ft: rs['speed_ft'],
      speed_m: rs['speed_m']
    }
  end

  def build_klasses(sheet)
    sheet.sheet_klasses.map do |sk|
      {
        id: sk.klass_id,
        name: sk.klass&.name,
        hit_die: sk.klass&.hit_die,
        level: sk.level,
        subclass: (sk.sub_klass ? { id: sk.sub_klass_id, name: sk.sub_klass&.name } : nil)
      }
    end
  end

  def build_proficiencies(sheet)
    meta = sheet.metadata || {}
    cs = meta['class_summary'] || {}
    rs = (meta['race_summary'] || {})
    bg = meta['background_summary'] || {}
    
    # Combine proficiencies from all sources
    tools = (cs['tools'] || []) + (bg['tools'] || [])
    languages = (rs['languages'] || []) + (bg['languages'] || [])

    # Race-specific extras from choices (best-effort)
    # Dwarf tool pick
    begin
      dwarf_tool = meta.dig('race_choices', 'dwarfTool')
      if dwarf_tool.present?
        tools << (dwarf_tool.is_a?(Hash) ? (dwarf_tool['name'] || dwarf_tool['id'] || dwarf_tool.to_s) : dwarf_tool.to_s)
      end
    rescue
    end
    # Variant Human: selected extra skill contributes to skills.race
    vh_skill = begin
      raw = meta.dig('race_choices', 'variantHumanSkill')
      raw.is_a?(Hash) ? (raw['name'] || raw['id']) : raw
    rescue
      nil
    end
    
    {
      armor: cs['armor_proficiencies'] || [],
      weapons: cs['weapon_proficiencies'] || [],
      tools: tools.uniq,
      languages: languages.uniq,
      skills: {
        class: cs['skills'] || [],
        background: bg['skills'] || [],
        race: [*(rs['proficiencies']&.dig('skills', 'fixed') || []), *([vh_skill].compact)]
      }
    }
  end

  def build_traits(sheet)
    meta = sheet.metadata || {}
    keys = (meta.dig('race_summary', 'traits') || [])
    return [] if keys.empty?
    Trait.where(api_index: keys).map { |t| { key: t.api_index, name: t.name } }
  end

  def build_background(sheet)
    meta = sheet.metadata || {}
    bg_summary = meta['background_summary'] || {}
    bg_name = meta['background'] || bg_summary['name']
    
    return nil unless bg_name.present?
    
    {
      name: bg_name,
      key: bg_summary['key'],
      skills: bg_summary['skills'] || [],
      tools: bg_summary['tools'] || [],
      languages: bg_summary['languages'] || [],
      equipment: bg_summary['equipment'] || [],
      feature: bg_summary['feature'] || {}
    }
  end

  def primary_sheet_klass
    # Heurística simples: primeiro registro (nível mais alto em caso de empate)
    @sheet.sheet_klasses.max_by { |sk| sk.level.to_i }
  end

  def build_conjuration(sheet, abilities:, prof:)
    sk = primary_sheet_klass
    return {} unless sk && sk.klass
    klass = sk.klass
    ability_key = (klass.spellcasting_ability || 'CHA').to_s.downcase
    mod = abilities[:mods][ability_key.to_sym] || 0
    atk_bonus = mod + prof
    dc = 8 + mod + prof

    name = (klass.name || '').downcase
    bard_like = (name.include?('bardo') || name.include?('bard'))
    inspiration_die = if sk.level.to_i >= 15 then 'd12' elsif sk.level.to_i >= 10 then 'd10' elsif sk.level.to_i >= 5 then 'd8' else 'd6' end
    song_rest_die = if sk.level.to_i >= 17 then 'd12' elsif sk.level.to_i >= 13 then 'd10' elsif sk.level.to_i >= 9 then 'd8' elsif sk.level.to_i >= 2 then 'd6' else nil end

    cl = ClassLevel.includes(:spellcasting).find_by(klass_id: klass.id, level: sk.level)
    slots = normalize_slots(cl&.spellcasting)

    meta_focus = (sheet.metadata || {}).dig('class_summary', 'spellcasting', 'focus') || (sheet.metadata || {}).dig('class_summary', 'focus')
    focus = meta_focus || (bard_like ? 'instrumento musical' : nil)

    {
      ability: ability_key.upcase,
      spell_attack_bonus: atk_bonus,
      spell_save_dc: dc,
      inspiration: (bard_like ? { die: inspiration_die, total: [1, (abilities[:mods][:cha] || 0)].max, used: 0 } : nil),
      song_of_rest_die: (bard_like ? song_rest_die : nil),
      focus: focus,
      slots: slots
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

  def build_features(sheet)
    char = sheet.character
    show_map = CharactersFeature.where(character_id: char.id).pluck(:feature_id, :id, :show).each_with_object({}) do |(fid, id, show), h|
      h[fid] = { id: id, show: (show != false) }
    end

    items = []
    sheet.sheet_klasses.each do |sk|
      klass = sk.klass
      next unless klass
      ClassLevel.includes(:features).where(klass_id: klass.id).where('level <= ?', sk.level.to_i).each do |cl|
        cl.features.each do |f|
          items << { id: f.id, level: cl.level, name: f.name, desc: f.description, source: 'Klass', show: (show_map[f.id]&.dig(:show) != false), pref_id: show_map[f.id]&.dig(:id) }
        end
      end
      if sk.sub_klass
        SubKlassLevel.includes(:features).where(sub_klass_id: sk.sub_klass_id).where('level <= ?', sk.level.to_i).each do |sl|
          sl.features.each do |f|
            items << { id: f.id, level: sl.level, name: f.name, desc: f.description, source: 'SubKlass', show: (show_map[f.id]&.dig(:show) != false), pref_id: show_map[f.id]&.dig(:id) }
        end
      end
      end
    end
    items.sort_by { |x| [x[:level].to_i, x[:name].to_s] }
  end

  def build_spells(sheet)
    # Persistidos
    known = SheetKnownSpell.joins(:spell, :sheet_klass).where(sheet_klasses: { sheet_id: sheet.id })
    by_level = Hash.new { |h,k| h[k] = [] }
    catalog = {}
    known.each do |ks|
      sp = ks.spell
      by_level[sp.level.to_i] << { id: sp.id, name: sp.name, desc: sp.desc, higher_level: sp.higher_level, description: sp.desc }
      catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
    end

    # Fallback via metadata
    if by_level.empty?
      per = (sheet.metadata || {}).dig('class_choices', 'per_level') || {}
      per.values.each do |row|
        (row['cantrips'] || []).each do |sp|
          level = (sp['level'] || 0).to_i
          name  = sp['name'] || sp['id']
          by_level[level] << { id: nil, name: name }
        end
        (row['spells'] || []).each do |sp|
          level = (sp['level'] || 1).to_i
          name  = sp['name'] || sp['id']
          by_level[level] << { id: nil, name: name }
        end
      end
      # Enrich fallback with spell descriptions where possible and fill catalog
      names = by_level.values.flatten.map { |h| h[:name] }.compact.uniq
      unless names.empty?
        Spell.where(name: names).find_each do |sp|
          by_level.each_value do |arr|
            arr.each do |entry|
              next unless entry[:name] == sp.name
              entry[:id] ||= sp.id
              entry[:desc] = sp.desc
              entry[:higher_level] = sp.higher_level
              entry[:description] = sp.desc
            end
          end
          catalog[sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
        end
      end
    end

    { known_by_level: by_level, catalog_by_id: catalog }
  end

  # Optional: complete catalog of class and subclass features by level (for UI lists)
  def build_feature_catalog
    sk = primary_sheet_klass
    return {} unless sk&.klass
    klass_levels = ClassLevel.includes(:features).where(klass_id: sk.klass_id).order(:level)
    cl = klass_levels.map do |row|
      { level: row.level, features: row.features.map { |f| { id: f.id, name: f.name, desc: f.description } } }
    end
    sl = []
    if sk.sub_klass_id
      sub_levels = SubKlassLevel.includes(:features).where(sub_klass_id: sk.sub_klass_id).order(:level)
      sl = sub_levels.map do |row|
        { level: row.level, features: row.features.map { |f| { id: f.id, name: f.name, desc: f.description } } }
      end
    end
    { class_levels: cl, sub_klass_levels: sl }
  end

  def build_feats(sheet)
    meta = sheet.metadata || {}
    feats = meta['feats'] || []

    # Also include feats from database associations
    sheet.sheet_feats.includes(:feat).each do |sheet_feat|
      feat = sheet_feat.feat
      feats << {
        id: sheet_feat.id,
        feat_id: feat.api_index,
        name: feat.name,
        description: feat.description,
        level_gained: sheet_feat.level_gained,
        ability_bonuses: sheet_feat.ability_bonuses,
        proficiency_bonuses: sheet_feat.proficiency_bonuses,
        cantrips: sheet_feat.choices_data&.dig('cantrips') || [],
        spells: sheet_feat.choices_data&.dig('spells') || [],
        features: feat.features_data,
        choices: sheet_feat.choices_data
      }
    end

    feats.uniq { |f| f[:feat_id] }
  end

  def sync_characters_features!
    sheet = @sheet
    sheet.sheet_klasses.includes(:klass).each do |sk|
      FeatureGrantService.call(sheet: sheet, klass: sk.klass, from_level: 0, to_level: sk.level)
    end
  end
end
