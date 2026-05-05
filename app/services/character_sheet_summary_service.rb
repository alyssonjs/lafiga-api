require 'set'

class CharacterSheetSummaryService
  prepend SimpleCommand

  def initialize(sheet_id:, sync: true)
    @sheet = Sheet.includes(
      :character,
      :alignment,
      :background,
      { race: :base_traits },
      { sub_race: :traits },
      sheet_klasses: [:klass, :sub_klass]
    ).find(sheet_id)
    @sync = sync
  end

  # Persiste str..cha nas colunas com o mesmo total que build_abilities (evita stub desatualizado).
  # Usa ignore do flag interno para sempre recalcular a partir de metadata antes de gravar.
  def self.sync_ability_columns_from_metadata!(sheet)
    inst = new(sheet_id: sheet.id, sync: false)
    abilities = inst.send(:build_abilities, sheet, ignore_authoritative_flag: true)
    scores = abilities[:scores] || {}
    meta = sheet.metadata || {}
    sheet.update!(
      str: scores[:str].to_i,
      dex: scores[:dex].to_i,
      con: scores[:con].to_i,
      int: scores[:int].to_i,
      wis: scores[:wis].to_i,
      cha: scores[:cha].to_i,
      metadata: meta.merge('ability_scores_include_all_increments' => true)
    )
  end

  def call
    ActiveRecord::Base.transaction do
      sync_sheet_hp_from_progression_if_behind! if @sync

      # Feature sync runs once inside FeaturesAggregator (FeatureGrantService).

      total_level = CharacterRules.total_level(@sheet)
      prof = CharacterRules.proficiency_bonus(total_level)

      abilities = build_abilities(@sheet)
      movement  = RaceProfileService.new(@sheet).call.slice(:speed_ft, :speed_m)
      klasses   = build_klasses(@sheet)

      conj = ClassProfileService.new(@sheet).call
      features = FeaturesAggregator.new(@sheet, sync: @sync).call
      spells = KnownSpellsAggregator.new(@sheet).call
      # Enrich conjuration with casting mode, list API and prepared limit;
      # Also provide full class spell list by level for prepared casters.
      begin
        pk = primary_sheet_klass
        if pk&.klass
          rules = ClassRules.find(pk.klass.api_index) || {}
          # mode: prefer feature_rules.spellcasting.mode, fallback to top-level preparation
          mode = (rules.dig(:feature_rules, :spellcasting, :mode) || rules.dig(:spellcasting, :preparation)).to_s
          # list_api: subclass override or class rules
          list_api = nil
          begin
            if pk.sub_klass&.api_index.present?
              entry = SubclassSpellcasting.lookup(
                klass_api: pk.klass.api_index,
                subclass_api: pk.sub_klass.api_index,
                level: pk.level
              )
              if entry
                list_api = entry.list_source_klass.to_s if entry.list_source_klass.present?
                # Third-caster archetypes learn/know spells (not prepared)
                conj[:mode] ||= 'known'
                # Override casting ability if subclass defines it (e.g., Arcane Trickster → INT)
                if entry.ability.present?
                  conj[:ability] = entry.ability.to_s.upcase
                end
                # Override slots if subclass provides its own progression (e.g., third-caster)
                if entry.slots.present? && entry.slots.is_a?(Hash)
                  arr = Array.new(9, 0)
                  entry.slots.each do |lvl, qty|
                    i = lvl.to_i
                    next if i <= 0 || i > 9
                    arr[i - 1] = qty.to_i
                  end
                  conj[:slots] = arr
                end
              end
            end
          rescue => _e
            # ignore
          end
          list_api ||= (rules.dig(:feature_rules, :spellcasting, :list) || rules.dig(:spellcasting, :list)).to_s

          conj[:mode] = mode if mode.present?
          conj[:list_api] = list_api if list_api.present?
          # Limite de preparadas: PHB preparadores (inclui Mago com modo spellbook no YAML).
          if %w[prepared spellbook].include?(mode.to_s)
            begin
              conj[:prepared_limit] = SpellRules.prepared_limit_for(@sheet, pk.klass).to_i
            rescue
            end
          end

          # For prepared casters, ship available spell names grouped by level to avoid extra client queries
          if conj[:mode] == 'prepared' && conj[:list_api].present?
            src_klass = Klass.find_by(api_index: conj[:list_api]) || pk.klass
            if src_klass
              ids = SpellSource.where(source_type: 'Klass', source_id: src_klass.id).pluck(:spell_id)
              unless ids.empty?
                by_lvl = Hash.new { |h,k| h[k] = [] }
                Spell.where(id: ids).find_each do |sp|
                  lvl = sp.level.to_i
                  by_lvl[lvl] << sp.name
                  spells[:catalog_by_id] ||= {}
                  spells[:catalog_by_id][sp.id] ||= { id: sp.id, name: sp.name, level: sp.level, desc: sp.desc, higher_level: sp.higher_level }
                end
                spells[:available_by_level] = {}
                by_lvl.each { |lvl, arr| spells[:available_by_level][lvl] = arr.uniq.sort }
              end
            end
          end
        end
      rescue => _e
        # best-effort enrichment only
      end
      equipment = begin
        EquipmentProfileService.new(@sheet).call
      rescue => e
        Rails.logger.warn "CharacterSheetSummaryService: EquipmentProfileService failed for sheet #{@sheet.id}: #{e.class} — #{e.message}"
        { inventory: [], equipped: {}, ac: { ac: (10 + CharacterRules.modifier(@sheet.dex)), source: 'Sem armadura' } }
      end

      # Fighting Style modifiers (AC, weapon bonuses)
      begin
        fs = FightingStyleRules.new(@sheet, equipment: equipment).call
        if fs[:ac_bonus].to_i > 0
          equipment[:ac] = (equipment[:ac] || {})
          equipment[:ac][:ac] = (equipment[:ac][:ac].to_i + fs[:ac_bonus].to_i)
          equipment[:ac][:source] = [equipment[:ac][:source], 'Estilo de Luta'].compact.join(' + ')
        end
        equipment[:mods] = fs
      rescue => _e
        # ignore FS computation errors
      end

      # Magic Items modifiers (AC, weapon bonuses)
      # IMPORTANTE: quando o ModifierPipeline está ON (default), o `EquippedItemProducer`
      # também consome `MagicItemRules.ac_bonus` e emite um Modifier `ac`. Para evitar
      # double-counting, NÃO aplicamos o ac_bonus aqui no caminho legado quando o
      # pipeline está ativo — o `bag.sum_for('ac')` mais abaixo é a fonte única.
      # Os `weapon_mods` continuam sendo aplicados aqui pois o frontend os consome
      # diretamente em `equipment[:mods][:weapon_mods]` (via `serverComputedAttackMods`).
      magic_pipeline_owns_ac = ENV['LAFIGA_MODIFIER_PIPELINE'].to_s != '0'
      begin
        mi = MagicItemRules.new(@sheet, equipment: equipment).call
        if mi[:ac_bonus].to_i > 0 && !magic_pipeline_owns_ac
          equipment[:ac] = (equipment[:ac] || {})
          equipment[:ac][:ac] = (equipment[:ac][:ac].to_i + mi[:ac_bonus].to_i)
          equipment[:ac][:source] = [equipment[:ac][:source], 'Itens Mágicos'].compact.join(' + ')
        end
        if mi[:weapon_mods]
          equipment[:mods] ||= {}
          equipment[:mods][:weapon_mods] ||= { main_hand: { attack: 0, damage: 0, offhand_add_ability: false }, off_hand: { attack: 0, damage: 0, offhand_add_ability: false } }
          [:main_hand, :off_hand].each do |hand|
            wm = equipment[:mods][:weapon_mods][hand] || { attack: 0, damage: 0 }
            add = (mi[:weapon_mods][hand] || {})
            wm[:attack] = wm[:attack].to_i + add[:attack].to_i
            wm[:damage] = wm[:damage].to_i + add[:damage].to_i
            equipment[:mods][:weapon_mods][hand] = wm
          end
        end
      rescue => _e
        # ignore magic item computation errors
      end

      # Draconic Resilience (Sorcerer - Draconic Bloodline): AC = 13 + DEX if unarmored
      begin
        pk = primary_sheet_klass
        if pk&.klass && pk&.sub_klass
          is_sorcerer = pk.klass.api_index.to_s == 'sorcerer'
          is_draconic = pk.sub_klass.api_index.to_s.include?('drac') || pk.sub_klass.name.to_s.downcase.include?('drac')
          armor_cat = (equipment.dig(:ac, :armor_category) || '').to_s.downcase
          unarmored = armor_cat.blank? || armor_cat == 'none'
          if is_sorcerer && is_draconic && unarmored
            dex_mod = begin (abilities[:mods] || {})[:dex].to_i rescue 0 end
            alt_ac = 13 + dex_mod
            cur_ac = equipment.dig(:ac, :ac).to_i
            if alt_ac > cur_ac
              equipment[:ac] ||= { ac: alt_ac, source: 'Resiliência Dracônica' }
              equipment[:ac][:ac] = alt_ac
              equipment[:ac][:source] = 'Resiliência Dracônica'
            end
          end
        end
      rescue => _e
        # ignore resilience computation errors
      end

      # Apply speed penalties from armor and encumbrance
      begin
        base_ft = movement[:speed_ft].to_i
        pen = 0
        pen += 10 if equipment.dig(:ac, :speed_penalty)
        pen += equipment.dig(:carry, :speed_penalty_ft).to_i
        if pen > 0 && base_ft > 0
          movement[:speed_ft] = [5, base_ft - pen].max
          # Convert to meters (1 ft = 0.3048 m)
          movement[:speed_m] = ((movement[:speed_ft].to_i * 0.3048).round(1))
        end
      rescue => _e
        # ignore movement adjustments if any error
      end

      # ─── Modifier Pipeline ─────────────────────────────────────────
      # ON por default. Opt-out via LAFIGA_MODIFIER_PIPELINE=0 (debug/A-B em dev).
      # Quando ativo, o resolver substitui completamente os helpers legados de
      # speed/AC vindos de feats e classes (KlassProducer cobre fast_movement,
      # FeatProducer cobre mobilidade/mestre_de_armas_duplas/etc.).
      modifier_bag = nil
      pipeline_disabled = ENV['LAFIGA_MODIFIER_PIPELINE'].to_s == '0'
      unless pipeline_disabled
        begin
          modifier_bag = Modifiers::ModifierResolver.new(
            @sheet,
            context: { equipment: equipment },
          ).call
        rescue => e
          Rails.logger.warn("CharacterSheetSummaryService: ModifierResolver falhou: #{e.class}: #{e.message}")
        end
      end

      # ─── Apply speed bonuses ───────────────────────────────────────
      if modifier_bag
        speed_bonus_ft = modifier_bag.sum_for('speed').to_i
        if speed_bonus_ft != 0
          movement[:speed_ft] = movement[:speed_ft].to_i + speed_bonus_ft
          movement[:speed_m]  = (movement[:speed_ft].to_i * 0.3048).round(1)
        end
      else
        # Legado: helpers escaneando metadata['feats'] e ClassRules.derive_feature_rules.
        # Mantidos como fallback quando flag está OFF (debug/A-B).
        begin
          feat_movement_bonus = apply_feat_movement_bonuses(@sheet)
          if feat_movement_bonus > 0
            movement[:speed_ft] = (movement[:speed_ft].to_i + feat_movement_bonus)
            movement[:speed_m]  = ((movement[:speed_ft].to_i * 0.3048).round(1))
          end
        rescue => _e
        end
        begin
          pk = primary_sheet_klass
          if pk&.klass
            armor_cat = (equipment.dig(:ac, :armor_category) || '').to_s.downcase
            armor_equipped = armor_cat.present? && armor_cat != 'none'
            ability_scores = begin
              sc = abilities[:scores] || {}
              { 'STR'=>sc[:str].to_i,'DEX'=>sc[:dex].to_i,'CON'=>sc[:con].to_i,
                'INT'=>sc[:int].to_i,'WIS'=>sc[:wis].to_i,'CHA'=>sc[:cha].to_i }
            rescue
              {}
            end
            derived = ClassRules.derive_feature_rules(
              rule: ClassRules.find(pk.klass.api_index) || {},
              level: pk.level.to_i.nonzero? || 1,
              picks: {},
              ability_scores: ability_scores,
              equipment: { armor_category: armor_cat, armor_equipped: armor_equipped }
            ) rescue {}
            bonus_m = (derived || {})[:speed_bonus_m].to_i
            if bonus_m != 0
              base_m = movement[:speed_m].to_f
              movement[:speed_m]  = (base_m + bonus_m).round(1)
              movement[:speed_ft] = (movement[:speed_m].to_f / 0.3048).round
            end
          end
        rescue => _e
        end
      end

      # ─── Apply AC bonuses from feats ───────────────────────────────
      if modifier_bag
        ac_bonus = modifier_bag.sum_for('ac').to_i
        if ac_bonus != 0
          equipment[:ac] = (equipment[:ac] || {})
          equipment[:ac][:ac]     = (equipment[:ac][:ac].to_i + ac_bonus)
          equipment[:ac][:source] = [equipment[:ac][:source], 'Modifiers'].compact.join(' + ')
        end
      else
        begin
          feat_ac_bonus = apply_feat_ac_bonuses(@sheet)
          if feat_ac_bonus > 0
            equipment[:ac] = (equipment[:ac] || {})
            equipment[:ac][:ac]     = (equipment[:ac][:ac].to_i + feat_ac_bonus)
            equipment[:ac][:source] = [equipment[:ac][:source], 'Feats'].compact.join(' + ')
          end
        rescue => _e
        end
      end

      alignment_idx = begin
        md = @sheet.metadata || {}
        (md.dig('alignment', 'index') || md['alignmentKey'] || md[:alignmentKey]).presence || @sheet.alignment&.api_index
      rescue StandardError
        @sheet.alignment&.api_index
      end

      saving_throws = build_saving_throws(@sheet)
      if modifier_bag
        saving_throws = (saving_throws + modifier_bag.granted('save')).uniq.sort
      end

      runtime_payload = begin
        @sheet.runtime!.as_payload
      rescue StandardError
        nil
      end

      {
        sheet: {
          id: @sheet.id,
          character_id: @sheet.character_id,
          name: @sheet.character&.name,
          hp_max: @sheet.hp_max,
          hp_current: @sheet.hp_current,
          temp_hp: @sheet.temp_hp,
          experience_points: @sheet.experience_points.to_i,
          alignment_index: alignment_idx,
          race: {
            id: @sheet.race_id,
            name: @sheet.race&.name,
            sub_race: (@sheet.sub_race ? { id: @sheet.sub_race_id, name: @sheet.sub_race&.name } : nil)
          }
        },
        runtime_state: runtime_payload,
        avatar_customization: @sheet.avatar_customization || {},
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
        equipment: equipment,
        proficiency_overrides: build_proficiency_overrides(pk, equipment, abilities),
        saving_throws: saving_throws,
        resources: build_resources(@sheet, abilities: abilities),
        **(modifier_bag ? {
          modifiers: {
            count: modifier_bag.size,
            saving_throws_granted: modifier_bag.granted('save'),
            # `speed_bonus` continua sendo o TOTAL (compativel com qualquer
            # consumidor antigo), mas adicionamos campos por origem para a UI
            # poder atribuir corretamente o bonus. Bug Adimael: a aba "Efeitos
            # de Itens Equipados" estava mostrando +10 ft do feat Mobilidade
            # porque so existia o campo agregado.
            speed_bonus: modifier_bag.sum_for('speed'),
            equipment_speed_bonus: modifier_bag.sum_for_kind('speed', source_kind: :item),
            feat_speed_bonus: modifier_bag.sum_for_kind('speed', source_kind: :feat),
            hp_per_level_bonus: modifier_bag.sum_for('hp.max_per_level'),
            ac_bonus_total: modifier_bag.sum_for('ac'),
            equipment_ac_bonus: modifier_bag.sum_for_kind('ac', source_kind: :item),
            feat_ac_bonus: modifier_bag.sum_for_kind('ac', source_kind: :feat),
            # ── Itens equipados: efeitos consolidados (Fase 2) ──
            resistances:            modifier_bag.granted('resistance'),
            damage_immunities:      modifier_bag.granted('damage_immunity'),
            damage_vulnerabilities: modifier_bag.granted('damage_vulnerability'),
            condition_immunities:   modifier_bag.granted('condition_immunity'),
            save_advantages:        modifier_bag.granted('advantage.save'),
            skill_advantages:       modifier_bag.granted('advantage.skill'),
            ability_bonuses: %w[str dex con int wis cha].each_with_object({}) { |ab, acc|
              v = modifier_bag.sum_for("ability.#{ab}")
              acc[ab] = v if v != 0
            },
            ability_sets: %w[str dex con int wis cha].each_with_object({}) { |ab, acc|
              v = modifier_bag.set_value("ability.#{ab}")
              acc[ab] = v if v && v.to_i > 0
            },
            passive_features: modifier_bag.matching('passive_feature').map(&:value),
            # Breakdown por target (para tooltips/inspeção):
            breakdown: {
              ac:    modifier_bag.to_breakdown('ac'),
              speed: modifier_bag.to_breakdown('speed'),
              hp_per_level: modifier_bag.to_breakdown('hp.max_per_level'),
            },
          },
        } : {}),
      }
    end
  rescue => e
    errors.add(:base, e.message)
    nil
  end

  private

  # Fichas antigas / pipeline com drift: colunas hp_* atrás do cálculo canónico
  # (per_level + Robustez Anã etc.). GET summary?sync=true autocorrige e devolve valores alinhados.
  def sync_sheet_hp_from_progression_if_behind!
    sk = @sheet.sheet_klasses.max_by { |x| x.level.to_i }
    return unless sk&.klass

    per_level = (@sheet.metadata || {}).dig('class_choices', 'per_level')
    return unless per_level.is_a?(Hash) && per_level.keys.any?

    character_level = @sheet.sheet_klasses.sum(&:level).to_i
    character_level = sk.level.to_i if character_level <= 0

    expected = SheetHpFromProgression.expected_max(@sheet, sk.klass, character_level, per_level)
    return if expected <= 0
    return if @sheet.hp_max.to_i >= expected

    prev_max = @sheet.hp_max.to_i
    cur = @sheet.hp_current.to_i
    new_cur = if prev_max <= 0 || cur <= 0 || cur == prev_max
                expected
              else
                [(expected * (cur.to_f / [prev_max, 1].max)).round, expected].min
              end
    @sheet.update!(hp_max: expected, hp_current: new_cur)
    @sheet.reload
  rescue StandardError => e
    Rails.logger.warn("CharacterSheetSummaryService: HP drift sync skipped: #{e.class}: #{e.message}")
  end

  def build_abilities(sheet, ignore_authoritative_flag: false)
    meta = sheet.metadata || {}
    authoritative = meta['ability_scores_include_all_increments'] && !ignore_authoritative_flag

    # Resolve o ponto de partida ("Dado/Base") para o breakdown:
    # - Se a flag authoritative esta ativa, as colunas (sheet.str etc.) ja somam tudo,
    #   entao precisamos do `base_ability_scores` no metadata para nao duplicar bonuses
    #   ao construir `sources`. Idem para `ignore_authoritative_flag` (sync recalculando).
    # - Sem flag e sem `base_ability_scores`, caimos nas colunas ja salvas (legado).
    stored_base = meta['base_ability_scores'] || meta[:base_ability_scores]
    base = if (authoritative || ignore_authoritative_flag) && stored_base.is_a?(Hash) && stored_base.keys.any?
             {
               str: (stored_base['str'] || stored_base[:str]).to_i,
               dex: (stored_base['dex'] || stored_base[:dex]).to_i,
               con: (stored_base['con'] || stored_base[:con]).to_i,
               int: (stored_base['int'] || stored_base[:int]).to_i,
               wis: (stored_base['wis'] || stored_base[:wis]).to_i,
               cha: (stored_base['cha'] || stored_base[:cha]).to_i
             }
           else
             {
               str: sheet.str.to_i,
               dex: sheet.dex.to_i,
               con: sheet.con.to_i,
               int: sheet.int.to_i,
               wis: sheet.wis.to_i,
               cha: sheet.cha.to_i
             }
           end

    # Track increments by source
    inc_total = { str: 0, dex: 0, con: 0, int: 0, wis: 0, cha: 0 }
    inc_race  = { str: 0, dex: 0, con: 0, int: 0, wis: 0, cha: 0 }
    inc_asi   = { str: 0, dex: 0, con: 0, int: 0, wis: 0, cha: 0 }
    feat_contribs = { str: [], dex: [], con: [], int: [], wis: [], cha: [] }

    # Race bonuses applied
    begin
      rb = meta['race_bonuses_applied'] || {}
      %i[str dex con int wis cha].each do |k|
        v = rb[k.to_s].to_i
        inc_race[k] += v
        inc_total[k] += v
      end
    rescue; end

    # ASIs from per-level choices
    begin
      abi_map = { 'STR'=>'str','DEX'=>'dex','DES'=>'dex','CON'=>'con','INT'=>'int','WIS'=>'wis','SAB'=>'wis','CHA'=>'cha','CAR'=>'cha' }
      short_map = { 'str'=>'str','dex'=>'dex','con'=>'con','int'=>'int','wis'=>'wis','cha'=>'cha' }
      per = (meta.dig('class_choices','per_level') || {}).values
      per.each do |row|
        asi = row.is_a?(Hash) ? row['asi'] : nil
        next unless asi.is_a?(Hash)
        mode = (asi['mode'] || asi[:mode]).to_s
        case mode
        when 'attributes'
          attrs = Array(asi['attributes'])
          if attrs.length == 1
            k = abi_map[attrs.first.to_s.upcase]
            if k
              inc_asi[k.to_sym] += 2
              inc_total[k.to_sym] += 2
            end
          else
            attrs.first(2).each do |a|
              k = abi_map[a.to_s.upcase]
              if k
                inc_asi[k.to_sym] += 1
                inc_total[k.to_sym] += 1
              end
            end
          end
        when 'plus2'
          ab = (asi['ability1'] || asi[:ability1]).to_s.downcase
          k = short_map[ab]
          if k
            inc_asi[k.to_sym] += 2
            inc_total[k.to_sym] += 2
          end
        when 'plus1x2'
          [asi['ability1'] || asi[:ability1], asi['ability2'] || asi[:ability2]].compact.each do |raw|
            ab = raw.to_s.downcase
            k = short_map[ab]
            if k
              inc_asi[k.to_sym] += 1
              inc_total[k.to_sym] += 1
            end
          end
        end
      end
    rescue; end

    # Ability bonuses from feats stored in metadata
    begin
      feats_meta = Array(meta['feats'])
      feats_meta.each do |f|
        fname = f['name'] || f[:name] || 'Talento'
        ab = f['ability_bonuses'] || {}
        ab.each do |k, v|
          key = k.to_s.downcase
          map = { 'str'=>:str, 'dex'=>:dex, 'con'=>:con, 'int'=>:int, 'wis'=>:wis, 'cha'=>:cha, 'for'=>:str, 'des'=>:dex, 'sab'=>:wis, 'car'=>:cha }
          sym = map[key]
          next unless sym
          val = v.to_i
          inc_total[sym] += val
          feat_contribs[sym] << { label: "Talento #{fname}", val: "+#{val}" }
        end
      end
    rescue; end

    # Final scores: quando `authoritative`, as colunas ja sao a fonte de verdade
    # (somadas previamente por `sync_ability_columns_from_metadata!`); caso contrario
    # somamos `base + inc_total` para o caminho legado.
    scores = if authoritative
               { str: sheet.str.to_i, dex: sheet.dex.to_i, con: sheet.con.to_i,
                 int: sheet.int.to_i, wis: sheet.wis.to_i, cha: sheet.cha.to_i }
             else
               base.each_with_object({}) { |(k, v), acc| acc[k] = v.to_i + inc_total[k].to_i }
             end
    mods = scores.transform_values { |v| CharacterRules.modifier(v) }

    # Sources breakdown for UI (sempre rico — independente da flag).
    sources = {}
    %i[str dex con int wis cha].each do |k|
      arr = []
      arr << { label: 'Dado/Base', val: base[k].to_i }
      arr << { label: 'Raça', val: "+#{inc_race[k]}" } if inc_race[k].to_i != 0
      arr << { label: 'Incrementos/ASIs', val: "+#{inc_asi[k]}" } if inc_asi[k].to_i != 0
      (feat_contribs[k] || []).each { |e| arr << e }
      # Drift-check: se o breakdown nao bate com a coluna autoritativa,
      # acrescenta linha de ajuste para o usuario nao ficar com soma quebrada.
      if authoritative
        breakdown_total = base[k].to_i + inc_total[k].to_i
        delta = scores[k].to_i - breakdown_total
        arr << { label: 'Ajuste manual', val: (delta.positive? ? "+#{delta}" : delta.to_s) } if delta != 0
      end
      sources[k] = arr
    end

    { base: base, scores: scores, mods: mods, sources: sources }
  end

  # Lista de habilidades com proficiência em salvaguarda (chaves em inglês: str, dex, …) para o cliente.
  def build_saving_throws(sheet)
    keys = Set.new
    abbrev_to_key = {
      'FOR' => 'str', 'STR' => 'str',
      'DES' => 'dex', 'DEX' => 'dex',
      'CON' => 'con',
      'INT' => 'int',
      'SAB' => 'wis', 'WIS' => 'wis',
      'CAR' => 'cha', 'CHA' => 'cha'
    }
    sheet.sheet_klasses.each do |sk|
      next unless sk.klass
      rule = ClassRules.find(sk.klass.api_index) || {}
      Array(rule[:saving_throws]).each do |st|
        raw = st.to_s.upcase.strip
        key = abbrev_to_key[raw]
        keys << key if key.present?
      end
    end
    keys.to_a.sort
  rescue
    []
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
        api_index: sk.klass&.api_index,
        hit_die: sk.klass&.hit_die,
        level: sk.level,
        subclass: (sk.sub_klass ? { id: sk.sub_klass_id, name: sk.sub_klass&.name, api_index: sk.sub_klass&.api_index } : nil),
        subclass_threshold: sk.klass&.subclass_level
      }
    end
  end

  def build_proficiency_overrides(pk, equipment, abilities)
    begin
      return {} unless pk&.klass
      armor_cat = (equipment.dig(:ac, :armor_category) || '').to_s.downcase
      armor_equipped = armor_cat.present? && armor_cat != 'none'
      sc = abilities[:scores] || {}
      ability_scores = {
        'STR' => sc[:str].to_i,
        'DEX' => sc[:dex].to_i,
        'CON' => sc[:con].to_i,
        'INT' => sc[:int].to_i,
        'WIS' => sc[:wis].to_i,
        'CHA' => sc[:cha].to_i,
      }
      derived = ClassRules.derive_feature_rules(
        rule: ClassRules.find(pk.klass.api_index) || {},
        level: pk.level.to_i.nonzero? || 1,
        picks: {},
        ability_scores: ability_scores,
        equipment: { armor_category: armor_cat, armor_equipped: armor_equipped }
      ) rescue {}
      (derived || {})[:proficiency_overrides] || {}
    rescue
      {}
    end
  end

  # Une dois hashes de class_summary preservando dados em ambos os lados:
  # arrays viram union (ordem da coluna primeiro), valores escalares a coluna
  # ganha quando o metadata vier vazio/nulo. Usado em build_proficiencies para
  # evitar que `metadata['class_summary'] = {}` (PATCH legado) anule a coluna.
  def deep_union_class_summary(col, meta)
    keys = (col.keys | meta.keys)
    out = {}
    keys.each do |k|
      cv = col[k]
      mv = meta[k]
      out[k] =
        if cv.is_a?(Array) || mv.is_a?(Array)
          (Array(cv) | Array(mv))
        elsif cv.is_a?(Hash) && mv.is_a?(Hash)
          deep_union_class_summary(cv, mv)
        elsif mv.respond_to?(:empty?) && mv.empty?
          cv
        else
          mv.nil? ? cv : mv
        end
    end
    out
  end

  def build_proficiencies(sheet)
    meta = sheet.metadata || {}
    cs_meta = meta['class_summary'].is_a?(Hash) ? meta['class_summary'] : {}
    cs_col = sheet.read_attribute(:class_summary)
    cs_col = {} unless cs_col.is_a?(Hash)
    # Coluna JSONB (provisioning canonical) UNIDA com metadata (PATCH antigo): para arrays
    # fazemos union; para escalares a coluna ganha quando o metadata estiver em branco
    # (evita o bug de `metadata['class_summary'] = {}` zerar profs vindas da rake).
    cs = deep_union_class_summary(cs_col.stringify_keys, cs_meta.stringify_keys)
    rs = (meta['race_summary'].presence || column_hash(sheet, :race_summary) || {})
    bg = (meta['background_summary'].presence || column_hash(sheet, :background_summary) || {})
    
    # Combine proficiencies from all sources
    to_arr = ->(v) { v.is_a?(Array) ? v : (v.nil? ? [] : [v]) }
    tools = to_arr.call(cs['tools']) + to_arr.call(bg['tools'])
    languages = to_arr.call(rs['languages']) + to_arr.call(bg['languages']) + to_arr.call(cs['languages'])

    # Race-specific extras from choices (best-effort)
    # Pick(s) de ferramenta(s) gravados pelo wizard sob `race_choices.chosenTools`
    # (estrutura atual; também aceitamos `dwarfTool` legado para compat com saves antigos).
    begin
      chosen_tools = Array(meta.dig('race_choices', 'chosenTools'))
      chosen_tools.each do |t|
        next if t.nil?
        name = t.is_a?(Hash) ? (t['name'] || t[:name] || t['id'] || t[:id]) : t
        tools << name.to_s if name.to_s.strip != ''
      end
    rescue
    end
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
    
    # Start with class summary and then merge subclass grants (armor/weapons)
    armor = Array(cs['armor_proficiencies'] || [])
    weapons = Array(cs['weapon_proficiencies'] || [])
    per_level_choices = meta.dig('class_choices', 'per_level') || {}

    # Mesclar proficiências da raça (armas/armaduras/ferramentas fixas) que vivem em
    # `race_summary.proficiencies` (populado pelo CharacterProvisioningService via RaceRules.apply).
    # Necessário para Anão (machado/martelo), drow (rapieira/besta), etc.
    begin
      race_profs = rs['proficiencies'] || {}
      weapons |= Array(race_profs['weapons']).map(&:to_s)
      armor   |= Array(race_profs['armor']).map(&:to_s)

      race_tools_block = race_profs['tools']
      if race_tools_block.is_a?(Hash)
        Array(race_tools_block['fixed']).each { |t| tools << t.to_s if t.to_s.strip != '' }
      elsif race_tools_block.is_a?(Array)
        race_tools_block.each { |t| tools << t.to_s if t.to_s.strip != '' }
      end
    rescue => _e
      # best-effort only
    end

    begin
      # Merge subclass proficiency grants up to current level
      # (yaml `subclass_overrides` → dnd import → SubKlass#levels_json).
      # Armor/weapons: sempre mergeados. Tools: ex. Maestria dos Autômatos nv2
      # (várias Ferramentas de * artesão no grants) — antes nem tools mergeava.
      # ficavam só no JSON e não apareciam em proficiencies.tools na ficha.
      sk = primary_sheet_klass
      if sk&.sub_klass && sk.sub_klass.levels_json.present?
        rows = JSON.parse(sk.sub_klass.levels_json) rescue []
        lvl = sk.level.to_i
        Array(rows).each do |row|
          rlevel = (row.is_a?(Hash) ? (row['level'] || row[:level]) : 0).to_i
          next if rlevel <= 0 || rlevel > lvl
          grants = (row['grants'] || {})
          prof = (grants['proficiencies'] || {})
          a = prof['armor'] || prof[:armor] || []
          w = prof['weapons'] || prof[:weapons] || []
          tlist = prof['tools'] || prof[:tools] || []
          armor |= resolve_proficiency_grant_values(
            a,
            per_level: per_level_choices,
            level: rlevel,
            choice_keys: %w[armor armors]
          )
          weapons |= resolve_proficiency_grant_values(
            w,
            per_level: per_level_choices,
            level: rlevel,
            choice_keys: %w[weapon weapons]
          )
          resolve_proficiency_grant_values(
            tlist,
            per_level: per_level_choices,
            level: rlevel,
            choice_keys: %w[tool tools instruments]
          ).each { |t| tools << t.to_s if t.to_s.strip != '' }
        end
      end
    rescue => _e
      # best-effort only
    end

    feat_skills = []

    # Merge feat-derived proficiencies (skills/tools/armor/shields/weapons)
    begin
      feats = Array(meta['feats'])
      feats.each do |f|
        pb = f['proficiency_bonuses'] || f[:proficiency_bonuses] || {}
        s = pb['skills'] || pb[:skills]
        feat_skills |= Array(s).map(&:to_s)
        t = pb['tools'] || pb[:tools]
        Array(t).each { |tool| tools << tool.to_s if tool.to_s.strip != '' }
        # Armor groups (e.g., ['leve','média','pesada'])
        a = pb['armors'] || pb[:armors]
        armor |= Array(a).map(&:to_s)
        # Shields: boolean true means add 'escudos'
        shields = pb['shields'] || pb[:shields]
        armor |= ['escudos'] if shields
        # Weapons: array of strings (e.g., 'armas marciais') or categories
        w = pb['weapons'] || pb[:weapons]
        weapons |= Array(w).map(&:to_s)
      end
    rescue => _e
      # ignore feat merge errors
    end

    # Race skills may be provided either as an array or as { fixed: [...] }
    race_skills = begin
      profs = rs['proficiencies'] || {}
      val = profs['skills']
      if val.is_a?(Hash)
        to_arr.call(val['fixed'])
      else
        to_arr.call(val)
      end
    rescue
      []
    end

    class_cs_skills = to_arr.call(cs['skills'])
    if class_cs_skills.blank?
      pl = meta['class_choices'] || meta[:class_choices] || {}
      per = pl['per_level'] || pl[:per_level] || {}
      r1 = per['1'] || per[1] || {}
      class_cs_skills = to_arr.call(r1['skills'] || r1[:skills]) if r1.is_a?(Hash)
    end

    # Perícias escolhidas no passo de raça (wizard) — ex.: Versatilidade do Meio-Elfo,
    # perícia extra do Humano Variante. Gravadas em metadata.race_choices.chosenSkills
    # (camelCase) ou chosen_skills; sem isto skills.race ficava só com fixas do summary.
    race_choice_skills = begin
      rc = meta['race_choices'] || meta[:race_choices] || {}
      rc = rc.deep_stringify_keys if rc.is_a?(Hash)
      rc ||= {}
      picks = []
      %w[chosenSkills chosen_skills].each do |key|
        Array(rc[key]).each do |item|
          next if item.nil?
          name = item.is_a?(Hash) ? (item['name'] || item['id']) : item
          s = name.to_s.strip
          picks << s unless s.empty?
        end
      end
      picks.uniq
    rescue StandardError
      []
    end

    {
      armor: armor,
      weapons: weapons,
      tools: tools.uniq,
      languages: languages.uniq,
      skills: {
        class: class_cs_skills,
        background: to_arr.call(bg['skills']),
        race: (race_skills + to_arr.call(vh_skill) + race_choice_skills).uniq,
        feat: feat_skills.uniq
      }
    }
  end

  def resolve_proficiency_grant_values(raw, per_level:, level:, choice_keys:)
    case raw
    when Hash
      h = raw.stringify_keys
      if h['choose'].to_i.positive?
        selected = selected_proficiency_choices(per_level, level, choice_keys)
        allowed = Array(h['options']).map(&:to_s).reject(&:blank?)
        selected = selected.select do |choice|
          allowed.blank? || allowed.any? { |option| normalized_proficiency_token(option) == normalized_proficiency_token(choice) }
        end
        return selected.first(h['choose'].to_i)
      end
      return Array(h['fixed']).map(&:to_s).reject(&:blank?) if h['fixed'].is_a?(Array)

      []
    when Array
      raw.flat_map do |entry|
        resolve_proficiency_grant_values(entry, per_level: per_level, level: level, choice_keys: choice_keys)
      end.uniq
    else
      value = raw.to_s.strip
      value.present? ? [value] : []
    end
  end

  def selected_proficiency_choices(per_level, level, choice_keys)
    row = per_level[level.to_s] || per_level[level] || {}
    return [] unless row.is_a?(Hash)

    choice_keys.flat_map do |key|
      Array(row[key] || row[key.to_sym]).map do |entry|
        if entry.is_a?(Hash)
          h = entry.stringify_keys
          (h['name'] || h['id']).to_s
        else
          entry.to_s
        end
      end
    end.map(&:strip).reject(&:blank?).uniq
  end

  def normalized_proficiency_token(value)
    value.to_s
         .unicode_normalize(:nfd)
         .gsub(/\p{Mn}/, '')
         .downcase
         .strip
  end

  def apply_feat_movement_bonuses(sheet)
    meta = sheet.metadata || {}
    feats = meta['feats'] || []
    total_bonus = 0

    feats.each do |feat|
      special_rules = feat['special_rules'] || {}
      movement_rules = special_rules['movement'] || {}
      
      # Check for speed bonus (e.g., from "mobilidade" feat)
      if movement_rules['speed_bonus']
        total_bonus += movement_rules['speed_bonus'].to_i
      end
    end

    total_bonus
  end

  def apply_feat_ac_bonuses(sheet)
    meta = sheet.metadata || {}
    feats = meta['feats'] || []
    total_bonus = 0

    feats.each do |feat|
      special_rules = feat['special_rules'] || {}
      equipment_rules = special_rules['equipment'] || {}
      
      # Check for AC bonus (e.g., from "mestre_de_armas_duplas" feat)
      if equipment_rules['equipment_ac_bonus']
        ac_bonus = equipment_rules['equipment_ac_bonus']
        if ac_bonus.is_a?(Hash) && ac_bonus['bonus']
          # Check if condition is met (e.g., "duas_armas")
          condition = ac_bonus['condition']
          if condition == 'duas_armas'
            # Check if character is wielding two weapons
            if is_dual_wielding?(sheet)
              total_bonus += ac_bonus['bonus'].to_i
            end
          else
            # No condition or other condition - apply bonus
            total_bonus += ac_bonus['bonus'].to_i
          end
        end
      end
    end

    total_bonus
  end

  def is_dual_wielding?(sheet)
    # Check if character has weapons in both main_hand and off_hand slots
    main_hand_weapon = SheetItem.where(sheet_id: sheet.id, equipped: true, slot: 'main_hand')
                                .where("category = 'weapon' OR item_name ILIKE '%arma%' OR item_name ILIKE '%sword%' OR item_name ILIKE '%dagger%' OR item_name ILIKE '%axe%' OR item_name ILIKE '%mace%' OR item_name ILIKE '%spear%' OR item_name ILIKE '%bow%' OR item_name ILIKE '%crossbow%'")
                                .first
    
    off_hand_weapon = SheetItem.where(sheet_id: sheet.id, equipped: true, slot: 'off_hand')
                               .where("category = 'weapon' OR item_name ILIKE '%arma%' OR item_name ILIKE '%sword%' OR item_name ILIKE '%dagger%' OR item_name ILIKE '%axe%' OR item_name ILIKE '%mace%' OR item_name ILIKE '%spear%' OR item_name ILIKE '%bow%' OR item_name ILIKE '%crossbow%'")
                               .first
    
    main_hand_weapon && off_hand_weapon
  end

  def allowed_trait_names_for_sheet(sheet)
    allowed = Set.new
    (sheet.race&.base_traits&.to_a || []).each { |tr| allowed.add(tr.name.to_s.downcase.strip) }
    if sheet.sub_race_id.present?
      (sheet.sub_race&.traits&.to_a || []).each { |tr| allowed.add(tr.name.to_s.downcase.strip) }
    end
    allowed
  end

  def build_traits(sheet)
    meta = sheet.metadata || {}
    rs = (meta['race_summary'].presence || column_hash(sheet, :race_summary) || {})
    raw_traits = rs['traits'] || []

    if raw_traits.is_a?(Array) && raw_traits.any?
      first = raw_traits.first
      if first.is_a?(Hash) && (first['name'] || first[:name])
        deduped = raw_traits.uniq { |t| (t['name'] || t[:name]).to_s.downcase.strip }
        if sheet.race_id.present?
          allowed = allowed_trait_names_for_sheet(sheet)
          if allowed.any?
            deduped = deduped.select { |t| allowed.include?((t['name'] || t[:name]).to_s.downcase.strip) }
          end
        end
        mapped = deduped.map { |t| { key: t['api_index'] || t['name'], name: t['name'] || t[:name], description: t['description'] || t[:description] } }
        return mapped if mapped.any?
      elsif raw_traits.all? { |x| x.is_a?(String) }
        traits_by_index = Trait.where(api_index: raw_traits.uniq).to_a
        if sheet.race_id.present?
          allowed = allowed_trait_names_for_sheet(sheet)
          if allowed.any?
            traits_by_index.select! { |t| allowed.include?(t.name.to_s.downcase.strip) }
          end
        end
        found = traits_by_index.map { |t| { key: t.api_index, name: t.name, description: t.description } }
        found.uniq! { |h| h[:name].to_s.downcase.strip }
        return found if found.any?
      end
    end

    # Fallback: base race traits (sub_race_id nil on race_traits) + selected subrace only
    if sheet.race_id.present?
      trait_records = sheet.race&.base_traits&.to_a || []
      trait_records += sheet.sub_race&.traits&.to_a || [] if sheet.sub_race_id.present?
      trait_records.uniq!(&:id)
      return trait_records.map { |t| { key: t.api_index, name: t.name, description: t.description } } if trait_records.any?
    end
    []
  end

  def build_background(sheet)
    meta = sheet.metadata || {}
    bg_summary = (meta['background_summary'].presence || column_hash(sheet, :background_summary) || {})
    bg_name = meta['background'] || bg_summary['name']
    
    return nil unless bg_name.present?
    
    {
      name: bg_name,
      key: bg_summary['key'],
      skills: bg_summary['skills'] || [],
      tools: bg_summary['tools'] || [],
      languages: bg_summary['languages'] || [],
      equipment: bg_summary['equipment'] || [],
      feature: bg_summary['feature'] || {},
      personality_traits: bg_summary['personality_traits'] || [],
      ideals: bg_summary['ideals'] || [],
      bonds: bg_summary['bonds'] || [],
      flaws: bg_summary['flaws'] || []
    }
  end

  def primary_sheet_klass
    # Mesmo critério que API/controller: nível desc, id asc em empate
    @primary_sk ||= @sheet.sheet_klasses.order(level: :desc, id: :asc).first
  end

  # Emite tabela `resources` consolidada por classe primária + nível atual.
  # Front consome via `summary.resources.{sorcery_points|bardic_inspiration|rage|ki|wild_shape|...}`.
  #
  # P2.13 (deprecacao gradual): a fonte canonica de USED passa a ser
  # `sheet.runtime_state.class_resources_used` (catalogo Fase C). O campo
  # `metadata['resources']` permanece como **fallback de leitura** apenas
  # para sheets antigos que ainda nao migraram. Escritas devem ir via
  # `Sheets::Runtime::DecrementResourceService` (que persiste em runtime_state)
  # ou via PATCH /runtime. A intencao eh remover `metadata['resources']` numa
  # migracao posterior, apos backfill, sem quebrar paridade exibida na UI.
  def build_resources(sheet, abilities:)
    sk = primary_sheet_klass
    return {} unless sk && sk.klass

    klass = sk.klass
    api_idx = (klass.api_index || klass.name).to_s.downcase
    level = sk.level.to_i
    raw_state = (sheet.metadata || {})['resources']
    legacy_state = raw_state.is_a?(Hash) ? raw_state : {}
    runtime_used = runtime_class_resources_used(sheet)

    used_for = lambda do |key|
      resource_used_value(legacy_state, runtime_used, key)
    end

    out = {}

    # Sorcery Points (Feiticeiro): PHB pg. 101 — 0@1, level a partir de nv 2
    if api_idx.include?('sorc') || api_idx == 'feiticeiro'
      total = level >= 2 ? level : 0
      out[:sorcery_points] = { total: total, used: [used_for.call('sorcery_points'), total].min }
    end

    # Bardic Inspiration (Bardo) — total = max(1, CHA mod); recarrega em descanso curto/longo
    if api_idx.include?('bard') || api_idx == 'bardo'
      total = [1, (abilities[:mods][:cha] || 0).to_i].max
      die = case
            when level >= 15 then 'd12'
            when level >= 10 then 'd10'
            when level >= 5  then 'd8'
            else 'd6'
            end
      out[:bardic_inspiration] = { total: total, used: [used_for.call('bardic_inspiration'), total].min, die: die }
    end

    # Rage (Bárbaro) — PHB pg. 49
    if api_idx.include?('barbar')
      total = case
              when level >= 20 then 999 # ilimitada
              when level >= 17 then 6
              when level >= 12 then 5
              when level >= 6  then 4
              when level >= 3  then 3
              else 2
              end
      damage = case
               when level >= 16 then 4
               when level >= 9  then 3
               else 2
               end
      out[:rage] = { total: total, used: [used_for.call('rage'), total].min, damage_bonus: damage }
    end

    # Ki (Monge)
    if api_idx.include?('monk') || api_idx == 'monge'
      total = level
      out[:ki] = { total: total, used: [used_for.call('ki'), total].min }
    end

    # Wild Shape (Druida) — usos por descanso curto: 2 (3 desde nv 20)
    if api_idx.include?('druid')
      total = level >= 20 ? 999 : 2
      out[:wild_shape] = { total: total, used: [used_for.call('wild_shape'), total].min }
    end

    # Channel Divinity (Clérigo/Paladino)
    if api_idx.include?('cleric') || api_idx == 'clerigo' || api_idx.include?('paladin')
      total = case
              when level >= 18 then 3
              when level >= 6  then 2
              else 1
              end
      out[:channel_divinity] = { total: total, used: [used_for.call('channel_divinity'), total].min }
    end

    # Action Surge + Second Wind + Indomitable (Guerreiro)
    if api_idx.include?('fighter') || api_idx == 'guerreiro'
      total = level >= 17 ? 2 : 1
      out[:action_surge] = { total: total, used: [used_for.call('action_surge'), total].min }
      out[:second_wind]  = { total: 1, used: [used_for.call('second_wind'), 1].min }

      if level >= 9
        ind_total = level >= 17 ? 3 : (level >= 13 ? 2 : 1)
        out[:indomitable] = { total: ind_total, used: [used_for.call('indomitable'), ind_total].min }
      end
    end

    # Divine Sense + Lay on Hands (Paladino)
    if api_idx.include?('paladin')
      cha_mod = (abilities[:mods][:cha] || 0).to_i
      ds_total = [1, 1 + cha_mod].max
      out[:divine_sense] = { total: ds_total, used: [used_for.call('divine_sense'), ds_total].min }

      loh_total = level * 5
      out[:lay_on_hands] = { total: loh_total, used: [used_for.call('lay_on_hands'), loh_total].min }
    end

    # Arcane Recovery (Mago)
    if api_idx.include?('wizard') || api_idx.include?('mago')
      out[:arcane_recovery] = {
        total: 1,
        used: [used_for.call('arcane_recovery'), 1].min,
        max_slot_levels: (level / 2.0).ceil,
      }
    end

    out
  rescue StandardError => e
    Rails.logger.warn("CharacterSheetSummaryService#build_resources: #{e.class}: #{e.message}")
    {}
  end

  # Lookup hibrido (P2.13): runtime_state tem precedencia sobre legado.
  # Quando ambos existem, runtime_state ganha (fonte unica de escrita).
  # Quando ambos faltam, retorna 0.
  def resource_used_value(legacy_state, runtime_used, key)
    if runtime_used && runtime_used.key?(key)
      runtime_used[key].to_i
    else
      (legacy_state.dig(key, 'used') || 0).to_i
    end
  end

  def runtime_class_resources_used(sheet)
    rs = sheet.runtime_state
    return nil unless rs
    raw = rs.class_resources_used
    raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : nil
  rescue StandardError
    nil
  end

  def build_conjuration(sheet, abilities:, prof:)
    sk = primary_sheet_klass
    return {} unless sk && sk.klass
    klass = sk.klass
    # Alinhado a ClassProfileService (subklass → DB → ClassRules → CHA).
    sub_ability = nil
    if sk.sub_klass&.api_index.present?
      ent = SubclassSpellcasting.lookup(
        klass_api: klass.api_index, subclass_api: sk.sub_klass.api_index, level: sk.level
      ) rescue nil
      sub_ability = ent&.ability if ent&.ability.present?
    end
    db_ab = klass.spellcasting_ability.to_s.strip.upcase
    db_ab = nil if db_ab.blank?
    rules_ab = ClassProfileService.spellcasting_ability_from_class_rules(klass.api_index)
    raw_ability = (sub_ability || db_ab || rules_ab || 'CHA').to_s
    # Normaliza para a chave curta (str/dex/.../cha). Antes era só `.downcase`,
    # o que deixava nomes como 'Inteligência' (PT-BR completo) cair em `mods[:inteligência]`
    # = nil → mod 0. Ver CharacterRules.normalize_ability_key.
    ability_key = CharacterRules.normalize_ability_key(raw_ability) || 'cha'
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
          items << { id: f.id, level: cl.level, name: f.localized_name, desc: f.localized_description, source: 'Klass', show: (show_map[f.id]&.dig(:show) != false), pref_id: show_map[f.id]&.dig(:id) }
        end
      end
      if sk.sub_klass
        SubKlassLevel.includes(:features).where(sub_klass_id: sk.sub_klass_id).where('level <= ?', sk.level.to_i).each do |sl|
          sl.features.each do |f|
            items << { id: f.id, level: sl.level, name: f.localized_name, desc: f.localized_description, source: 'SubKlass', show: (show_map[f.id]&.dig(:show) != false), pref_id: show_map[f.id]&.dig(:id) }
          end
        end
      end
    end

    items = items.sort_by { |x| [x[:level].to_i, x[:name].to_s] }

    # Fallback A: se não houver registros de classe/subclasse no BD, tentar metadados.features_by_level
    if items.empty?
      begin
        meta = sheet.metadata || {}
        fbl = meta['features_by_level'] || {}
        # Espera-se um hash { "1": [{id,name,desc}, ...], "2": [...] }
        (fbl.keys.map(&:to_i).sort).each do |lvl|
          Array(fbl[lvl.to_s]).each do |f|
            nm = (f.is_a?(Hash) ? (f['name'] || f[:name]) : f)
            desc = (f.is_a?(Hash) ? (f['desc'] || f[:desc] || f['description'] || f[:description]) : nil)
            next unless nm.present?
            items << { id: (f.is_a?(Hash) ? (f['id'] || f[:id]) : nil), level: lvl, name: nm, desc: desc, source: 'metadata', show: true, pref_id: nil }
          end
        end
      rescue => _e
        # ignore fallback errors
      end
    end

    # Fallback B: se ainda estiver vazio, derivar de class_summary em metadata usando catálogos (ClassLevel/SubKlassLevel)
    if items.empty?
      begin
        meta = sheet.metadata || {}
        cs = meta['class_summary'] || {}
        # Identificar classe por id ou api_index
        klass = nil
        kid = cs['klass_id'] || cs[:klass_id] || cs['id'] || cs[:id]
        if kid.present?
          if kid.to_s =~ /\A\d+\z/
            klass = Klass.find_by(id: kid.to_i)
          else
            klass = Klass.find_by(api_index: kid.to_s)
          end
        end
        if klass.nil?
          # tentar por nome
          kname = (cs['name'] || cs[:name]).to_s
          klass = Klass.where('LOWER(name) = ? OR LOWER(name) LIKE ?', kname.downcase, "%#{kname.downcase}%").first if kname.present?
        end
        # Nível atual proveniente do metadata, como fallback
        lvl = (meta['current_level'] || meta[:current_level]).to_i
        lvl = 1 if lvl <= 0
        if klass
          ClassLevel.includes(:features).where(klass_id: klass.id).where('level <= ?', lvl).each do |cl|
            cl.features.each do |f|
              items << { id: f.id, level: cl.level, name: f.localized_name, desc: f.localized_description, source: 'Klass', show: true, pref_id: nil }
            end
          end
          # Subclasse pelo summary (aceitar id numérico, slug ou nome)
          sub_ident = cs['subclass_id'] || cs[:subclass_id] || cs['subclass'] || cs[:subclass]
          sub = nil
          if sub_ident.present?
            s = sub_ident.to_s
            if s =~ /\A\d+\z/
              sub = SubKlass.find_by(id: s.to_i)
            else
              sub = SubKlass.where(klass_id: klass.id).find_by(api_index: s) ||
                    SubKlass.where(klass_id: klass.id).find_by(api_index: s.tr('_','-')) ||
                    SubKlass.where(klass_id: klass.id).find_by(api_index: s.tr('-','_'))
              if sub.nil?
                sub = SubKlass.where(klass_id: klass.id).where('LOWER(name) = ? OR LOWER(name) LIKE ?', s.downcase, "%#{s.downcase}%").first
              end
            end
          end
          if sub
            SubKlassLevel.includes(:features).where(sub_klass_id: sub.id).where('level <= ?', lvl).each do |sl|
              sl.features.each do |f|
                items << { id: f.id, level: sl.level, name: f.localized_name, desc: f.localized_description, source: 'SubKlass', show: true, pref_id: nil }
              end
            end
          end
        end
      rescue => _e
        # best-effort
      end
    end

    items
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
      { level: row.level, features: row.features.map { |f| { id: f.id, name: f.localized_name, desc: f.localized_description } } }
    end
    sl = []
    if sk.sub_klass_id
      sub_levels = SubKlassLevel.includes(:features).where(sub_klass_id: sk.sub_klass_id).order(:level)
      sl = sub_levels.map do |row|
        { level: row.level, features: row.features.map { |f| { id: f.id, name: f.localized_name, desc: f.localized_description } } }
      end
    end
    { class_levels: cl, sub_klass_levels: sl }
  end

  def build_feats(sheet)
    feats = []

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

    # De-dup feats coming from metadata (string keys) and DB (symbol keys)
    # Ensure we consider both symbol and string keys when uniquing by feat_id
    feats.uniq { |f| f[:feat_id] || f['feat_id'] }
  end

  def column_hash(sheet, column)
    return nil unless sheet.respond_to?(column)
    val = sheet.send(column)
    val.is_a?(Hash) && val.present? ? val.stringify_keys : nil
  rescue
    nil
  end
end
