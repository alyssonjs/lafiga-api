class LevelUpService
  prepend SimpleCommand
  require 'ostruct'

  # Params:
  # - sheet_id: ficha do personagem
  # - klass_id: classe a evoluir
  # - levels: quantos níveis subir (default 1)
  # - sub_klass_id: definir subclasse (opcional; respeita o threshold)
  # - hp_rolls: array/num para HP ganho (opcional). Se ausente, usa média fixa (round up).
  def initialize(sheet_id:, klass_id:, levels: 1, sub_klass_id: nil, hp_rolls: nil)
    @sheet = Sheet.find(sheet_id)
    @klass = Klass.find(klass_id)
    @levels = levels.to_i
    @sub_klass_id = sub_klass_id
    @hp_rolls = hp_rolls
  end

  # Pré-materializa truques/magias conhecidas exigidas em Spellcasting@L1 antes do
  # primeiro passo do `LevelUpService#call`. O `LevelUpGuardService` valida o nível
  # atual *antes* de incrementar — sem isso, bruxo/bardo/feiticeiro ficam sem
  # `SheetKnownSpell` e o guard falha com "Magias conhecidas: selecione N".
  def self.seed_level_one_known_spells!(sheet_id:, klass_id:)
    sheet = Sheet.find_by(id: sheet_id)
    klass = Klass.find_by(id: klass_id)
    return unless sheet && klass

    sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
    return unless sk

    inst = new(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
    inst.send(:persist_known_spells!, sk, from_level: 1, to_level: 1)
  end

  def call
    ActiveRecord::Base.transaction do
      sk = @sheet.sheet_klasses.find_or_initialize_by(klass_id: @klass.id)
      # Garantir FK: em alguns casos o registro novo não recebe sheet_id antes do primeiro save.
      if sk.new_record?
        raise StandardError, 'Sheet sem id ao evoluir classe' if @sheet.id.blank?

        sk.sheet = @sheet
      end
      total_other = @sheet.sheet_klasses.where.not(id: sk.id).sum(:level)
      
      Rails.logger.info "LevelUpService: sheet_id=#{@sheet.id}, klass_id=#{@klass.id}, levels=#{@levels}, sub_klass_id=#{@sub_klass_id}"

      # Loop de incremento nível a nível para validar pré-requisitos a cada passo
      con_mod = CharacterRules.modifier(@sheet.con)
      hit_die = @klass.hit_die.to_i.nonzero? || 8
      gained_hp = 0
      rolls = Array(@hp_rolls).first(@levels)
      
      Rails.logger.info "LevelUpService: con_mod=#{con_mod}, hit_die=#{hit_die}, gained_hp=#{gained_hp}"

      @levels.times do |i|
        current_level = sk.level.to_i.nonzero? || 0
        new_level = current_level + 1

        # Capa: valida soma total ≤ 20 (model também valida)
        raise StandardError, 'Total de níveis excede 20' if (total_other + new_level) > 20

        # Garantir que requisitos do nível atual estejam preenchidos (auto-pick best-effort)
        ensure_level_requirements!(sk, current_level)

        # Verificar que o nível atual está completo antes de avançar
        Rails.logger.info "Calling LevelUpGuardService for level #{current_level}"
        guard = LevelUpGuardService.call(sheet: @sheet, klass: @klass)
        unless guard.success?
          Rails.logger.error "LevelUpGuardService failed: #{guard.errors.full_messages.join('; ')}"
          raise StandardError, guard.errors.full_messages.join('; ')
        end
        Rails.logger.info "LevelUpGuardService passed for level #{current_level}"

        # Avançar 1 nível (antes de definir subclasse para satisfazer validação do model)
        prev = current_level
        sk.update!(level: new_level)

        # Atribuir subclasse se solicitada (via param ou metadata) e elegível neste passo
        meta = @sheet.metadata || {}
        meta_choice = meta.dig('class_choices', 'subclass_id')
        chosen_identifier = @sub_klass_id.presence || meta_choice
        if chosen_identifier.present?
          threshold = @klass.try(:subclass_level).to_i
          if threshold > 0 && new_level < threshold
            Rails.logger.warn "Subclasse solicitada no nível #{new_level}, mas threshold é #{threshold}. Aguardando nível adequado."
            # Não definir subclasse ainda, mas não falhar
          else
            sub = find_subklass!(chosen_identifier)
            raise StandardError, 'Subclasse inválida para esta classe' unless sub.klass_id == @klass.id
            sk.update!(sub_klass_id: sub.id)
            Rails.logger.info "Subclasse #{sub.name} definida no nível #{new_level}"
          end
        end

        # Fazer escolhas automáticas se necessário
        Rails.logger.info "Calling AutoChoiceService for level #{new_level}"
        auto_choice = AutoChoiceService.call(sheet: @sheet, klass: @klass, level: new_level)
        unless auto_choice.success?
          Rails.logger.warn "AutoChoiceService failed: #{auto_choice.errors.full_messages.join('; ')}"
        end
        Rails.logger.info "AutoChoiceService completed for level #{new_level}"

        # Conceder features deste delta
        Rails.logger.info "Calling FeatureGrantService from_level=#{prev}, to_level=#{new_level}"
        FeatureGrantService.call(sheet: @sheet, klass: @klass, from_level: prev, to_level: new_level)
        Rails.logger.info "FeatureGrantService completed for level #{new_level}"

        # Aplicar ASI-as-feat se o per_level[new_level].asi.mode == 'feat'.
        # Antes desta chamada, escolher Observador no nivel 4 (caso "Adimael")
        # gravava apenas a string em per_level[4].asi.featId — sem SheetFeat,
        # sem entrada em metadata['feats'], sem soma em abilities[:scores].
        # Ver spec/services/level_up_service_feats_spec.rb.
        asi_result = AsiFeatApplier.call(sheet: @sheet.reload, level: new_level)
        if asi_result.applied
          Rails.logger.info "AsiFeatApplier applied feat at level #{new_level}: #{asi_result.sheet_feat&.feat&.api_index}"
        end

        # Persistir magias conhecidas escolhidas para este nível (se houver)
        Rails.logger.info "Calling persist_known_spells! for level #{new_level}"
        persist_known_spells!(sk, from_level: new_level, to_level: new_level)
        Rails.logger.info "persist_known_spells! completed for level #{new_level}"

        # Check for new racial spells unlocked at this level (Drow level 3, 5 etc)
        if @sheet.race_id.present?
          begin
            race_rule = RaceRules.apply(
              race_id: @sheet.race.api_index,
              subrace_id: @sheet.sub_race&.api_index,
              choices: (@sheet.metadata || {})['race_choices'] || {}
            )
            RacialSpellsService.call(
              sheet: @sheet, 
              race_rule: race_rule, 
              character_level: new_level
            )
            Rails.logger.info "RacialSpellsService completed for level #{new_level}"
          rescue => e
            Rails.logger.warn "Failed to update racial spells on level up: #{e.message}"
          end
        end

        # HP ganho neste passo
        step_gain = if rolls.present? && rolls[i]
          rolls[i].to_i + con_mod
        else
          (hit_die / 2.0).ceil + con_mod
        end
        # Feiticeiro (Linhagem Dracônica): +1 HP por nível de feiticeiro
        begin
          if @klass.api_index.to_s == 'sorcerer'
            is_draconic = false
            # subclasse pode ter sido definida neste passo
            if sk.sub_klass
              api = sk.sub_klass.api_index.to_s
              nm  = sk.sub_klass.name.to_s.downcase
              is_draconic = api.include?('drac') || nm.include?('drac')
            end
            step_gain += 1 if is_draconic
          end
        rescue => _e
          # best-effort; não falhar o level up por isso
        end
        # Robustez Anã (Anão da Colina) e outros traços com grants.hp_per_level em RaceRules — +PV em todo nível
        begin
          rp = RacialHpBonus.per_level_for_sheet(@sheet)
          step_gain += rp if rp.positive?
        rescue => _e
          Rails.logger.warn("LevelUpService: racial HP bonus omitido (#{_e.class})") if defined?(Rails.logger)
        end
        gained_hp += step_gain
      end

      # Aplicar total de HP acumulado
      @sheet.update!(hp_max: @sheet.hp_max + gained_hp, hp_current: [@sheet.hp_current + gained_hp, @sheet.hp_max + gained_hp].min)

      # Sincronizar nível total do personagem na coluna sheets.current_level + metadata
      @sheet.reload
      total_char_level = @sheet.sheet_klasses.sum(:level)
      meta_lv = @sheet.metadata || {}
      @sheet.update!(
        current_level: total_char_level,
        metadata: meta_lv.merge('current_level' => total_char_level)
      )

      # Atualizar colunas de atributos com o mesmo cálculo do resumo (evita divergência stub vs summary)
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(@sheet)

      # Atualizar recursos calculados (ex.: Fúria do Bárbaro)
      Rails.logger.info "Calling CharacterResourcesService"
      CharacterResourcesService.new(@sheet).call(persist: true)
      Rails.logger.info "CharacterResourcesService completed"

      sk
    end
  rescue StandardError => e
    errors.add(:base, e.message)
    nil
  end

  private

  def find_subklass!(identifier)
    str = identifier.to_s
    if str.match?(/\A\d+\z/)
      SubKlass.find(str.to_i)
    else
      base = SubklassSlugResolver.normalize(str.downcase)
      synonyms = {
        'eldritch_knight' => ['eldritch_knight','eldritch-knight','cavaleiro-arcano','cavaleiro_arcano','cavaleiro arcano'],
        'battle_master'   => ['battle_master','battlemaster','mestre-de-batalha','mestre_de_batalha','mestre de batalha'],
        'battlemaster'    => ['battle_master','battlemaster','mestre-de-batalha','mestre_de_batalha','mestre de batalha']
      }
      candidates = [base, base.tr('_','-'), base.tr('-','_')]
      candidates += (synonyms[base] || [])
      candidates = candidates.map(&:downcase).uniq
      candidates = SubklassSlugResolver.with_wizard_evocation_aliases(@klass.api_index, candidates)

      scope = SubKlass.where(klass_id: @klass.id)
      sub = scope.where('LOWER(api_index) IN (?)', candidates).first
      if sub.nil?
        sub = SubKlass.where('LOWER(api_index) IN (?)', candidates).first
      end
      if sub.nil?
        candidates.each do |q|
          sub = scope.where('LOWER(name) = ? OR LOWER(name) LIKE ?', q, "%#{q}%").first
          break if sub
        end
      end
      if sub.nil?
        candidates.each do |q|
          sub = SubKlass.where('LOWER(name) = ? OR LOWER(name) LIKE ?', q, "%#{q}%").first
          break if sub
        end
      end
      raise ActiveRecord::RecordNotFound, "SubKlass '#{str}' não encontrada" unless sub
      sub
    end
  end

  def persist_known_spells!(sk, from_level:, to_level:)
    meta = @sheet.metadata || {}
    per = meta.dig('class_choices', 'per_level') || {}
    resolver = SpellResolver.new
    metadata_dirty = false

    # Phase 12 (causa raiz spells): antes, este metodo descartava silenciosamente
    # qualquer entry cujo `id` nao fosse numerico (ex.: `{"id"=>"Toque arrepiane"}`,
    # vindo de import por nome). A magia ficava orfa em metadata sem virar
    # `SheetKnownSpell`. Agora cada entry passa por SpellResolver (id/name/lower/
    # slug/translation/aliases) e, quando resolve, regrava `{id:Int, name:String}`
    # canonico no metadata (auto-heal) — proxima leitura ja entra direto pelo path
    # de id numerico. Quando NAO resolve, loga warn (em vez de silencio).
    process_picks = lambda do |row, key, default_level|
      Array(row[key]).each_with_index do |sp, idx|
        sid_numeric = case sp
                      when Numeric then sp.to_i
                      when Hash    then (sp['id'] || sp[:id]).is_a?(Integer) ? (sp['id'] || sp[:id]) :
                                          ((sp['id'] || sp[:id]).to_s =~ /\A\d+\z/ ? (sp['id'] || sp[:id]).to_i : nil)
                      else nil
                      end

        if sid_numeric&.positive?
          SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sid_numeric)
          next
        end

        normalized = resolver.normalize(sp)
        if normalized.nil?
          name_for_log = sp.is_a?(Hash) ? (sp['name'] || sp[:name] || sp['id'] || sp[:id]) : sp
          Rails.logger.warn(
            "LevelUpService: spell nao resolvida em sheet=#{@sheet.id} sk=#{sk.id} " \
            "level=#{default_level} key=#{key} idx=#{idx} input=#{name_for_log.inspect}. " \
            'Adicione um alias em config/spell_aliases.yml ou corrija a fonte.'
          )
          next
        end

        SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: normalized[:id])

        # Auto-heal: regrava o metadata in-place para nao precisar resolver de novo.
        canonical = { 'id' => normalized[:id], 'name' => normalized[:name], 'level' => normalized[:level] }
        if sp != canonical
          row[key][idx] = canonical
          metadata_dirty = true
        end
      end
    end

    (from_level..to_level).each do |lvl|
      row = per[lvl.to_s] || {}
      process_picks.call(row, 'cantrips', lvl)
      process_picks.call(row, 'spells',   lvl)

      # Auto-preencher até o limite do nível (se faltando escolhas) para classes de magias conhecidas
      sc = SpellRules.sc_for(@klass, lvl)
      # Fallback: se não houver spellcasting base, verificar progressão por subclasse
      if sc.nil?
        begin
          entry = SpellRules.subclass_sc_for(sk)
          if entry
            # Construir shape compatível para limites e slots
            sc = OpenStruct.new(
              cantrips_known: entry.cantrips_known,
              spells_known: entry.spells_known,
              spell_slots: entry.slots
            )
          end
        rescue => _e
        end
      end
      next unless sc
      limits = { spells: sc.spells_known, cantrips: sc.cantrips_known }
      counts = SpellRules.known_counts_for(sk)

      class_spell_ids = SpellSource.where(source_type: 'Klass', source_id: @klass.id).pluck(:spell_id)
      pool = Spell.where(id: class_spell_ids)

      # Cantrips
      if limits[:cantrips]
        need = [limits[:cantrips].to_i - counts[:cantrips].to_i, 0].max
        if need > 0
          cands = pool.where(level: 0).where.not(id: SheetKnownSpell.where(sheet_klass_id: sk.id).select(:spell_id)).to_a
          cands.sample(need).each do |sp|
            SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sp.id)
            counts[:cantrips] += 1
          end
        end
      end

      # Spells > 0 respeitando gate de nível
      if limits[:spells]
        need = [limits[:spells].to_i - counts[:spells].to_i, 0].max
        if need > 0
          gate_level = SpellRules.gate_for(@sheet, @klass)
          cands = pool.where('level > 0 AND level <= ?', gate_level)
                       .where.not(id: SheetKnownSpell.where(sheet_klass_id: sk.id).select(:spell_id))
                       .to_a
          cands.sample(need).each do |sp|
            SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sp.id)
            counts[:spells] += 1
          end
        end
      end

      # Wizard spellbook progression: learn fixed number of spells per level
      begin
        if @klass.api_index == 'wizard'
          rule = ClassRules.find(@klass.api_index) || {}
          learn = rule.dig(:feature_rules, :spellbook_progression, :learn_on_level_up).to_i
          if learn > 0
            # Candidates: class list up to the gate for this level, excluding already known
            gate_level = SpellRules.gate_for(@sheet, @klass)
            candidates = pool.where('level > 0 AND level <= ?', gate_level)
                              .where.not(id: SheetKnownSpell.where(sheet_klass_id: sk.id).select(:spell_id))
                              .to_a
            # If ClassLevel also defined a known limit for this level and we already auto-filled above,
            # we still top-up with the spellbook progression for Wizards.
            candidates.sample(learn).each do |sp|
              SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sp.id)
            end
          end
        end
      rescue => _e
        # best-effort only; do not fail level up on wizard spellbook errors
      end
    end

    # Auto-heal: persiste o metadata canonicalizado quando o resolver substituiu
    # entries (string crua / hash com id textual) por `{id, name, level}` reais.
    # Usa update_column para nao re-disparar callbacks/version-bump.
    if metadata_dirty
      meta_to_save = (@sheet.metadata || {}).deep_dup
      meta_to_save['class_choices'] ||= {}
      meta_to_save['class_choices']['per_level'] = per
      @sheet.update_column(:metadata, meta_to_save)
      Rails.logger.info "LevelUpService: auto-healed spell entries em metadata sheet=#{@sheet.id} sk=#{sk.id}"
    end
  rescue => e
    Rails.logger.warn("Known spells persist skipped: #{e.message}")
  end

  # Best-effort auto-pick para evitar bloqueios triviais quando metadados existem mas escolhas faltam
  # Resolve `options` (Symbol/Array) para uma lista de strings utilizáveis no auto-fill.
  # - Symbol → tenta ClassChoicesCatalog (canonical_names) primeiro, fallback p/ ClassRules.dictionaries
  # - Array  → como veio
  def resolve_choice_options_for_autofill(options)
    case options
    when Symbol
      catalog_path = File.join(ClassChoicesCatalog::CONFIG_DIR, "#{options}.yml") rescue nil
      if catalog_path && File.exist?(catalog_path)
        return ClassChoicesCatalog.canonical_names(options)
      end
      case options
      when :invocations_core
        ['Agonizing Blast','Armor of Shadows','Devil\'s Sight','Fiendish Vigor','Mask of Many Faces','Mire the Mind']
      else
        Array(ClassRules.dictionaries[options] || [])
      end
    else
      Array(options)
    end
  end

  def ensure_level_requirements!(sk, current_level)
    meta = @sheet.metadata || {}
    meta['class_choices'] ||= {}
    meta['class_choices']['per_level'] ||= {}
    rule = ClassRules.find(@klass.api_index) || {}

    # 1) nível 1: perícias e instrumentos
    if current_level >= 1
      need_sk = rule.dig(:skill_proficiencies, :choose).to_i
      if need_sk > 0
        # per_level['1'].skills é a fonte canónica (gravada pelo wizard); só caímos para os
        # campos root quando o per_level estiver vazio (saves antigos / fluxos legacy).
        per_lvl1_skills = meta.dig('class_choices', 'per_level', '1', 'skills') || []
        pick_src = per_lvl1_skills.presence || meta['class_choices']['skills_selected'] || meta['class_choices']['skills'] || []
        arr = Array(pick_src).map { |x| x.is_a?(Hash) ? (x['name'] || x[:name]) : x }.compact
        if arr.size < need_sk
          options = if rule.dig(:skill_proficiencies, :options) == :any
                      ClassRules.dictionaries[:skills_all]
                    else
                      Array(rule.dig(:skill_proficiencies, :options))
                    end
          # Só preenchemos root quando per_level['1'] também estiver vazio — evita criar
          # discrepância entre per_level['1'].skills e class_choices.skills_selected.
          if per_lvl1_skills.blank?
            meta['class_choices']['skills_selected'] = options.sample(need_sk)
          end
        end
      end
      inst_need = rule.dig(:tool_proficiencies, :instruments, :choose).to_i rescue 0
      if inst_need > 0
        pick_src = (meta['class_choices']['instruments_selected'] || meta['class_choices']['instruments'] || [])
        arr = Array(pick_src).map { |x| x.is_a?(Hash) ? (x['name'] || x[:name]) : x }.compact
        if arr.size < inst_need
          meta['class_choices']['instruments_selected'] = ClassRules.dictionaries[:instruments].sample(inst_need)
        end
      end
    end

    # 2) Escolhas obrigatórias por nível atual (fighting_style, metamagic, invocations, pact_boon)
    required = (rule[:required_choices_at_level] || {})[current_level]
    if required.present?
      row = (meta['class_choices']['per_level'][current_level.to_s] ||= {})
      required.each do |key, conf|
        next if row[key.to_s].present? || meta['class_choices'][key.to_s].present?
        count = conf[:choose].to_i
        next if count <= 0
        options = conf[:options]
        list = resolve_choice_options_for_autofill(options)
        row[key.to_s] = list.sample(count)
        # propaga top-level fighting_style para compatibilidade
        if key.to_s == 'fighting_style' && meta['class_choices']['fighting_style'].blank?
          meta['class_choices']['fighting_style'] = row[key.to_s]
        end
      end
    end

    # 3) Magias/cantrips mínimos exigidos no nível atual (classes de known)
    sc = SpellRules.sc_for(@klass, current_level)
    if sc
      # cantrips
      can_need = sc.cantrips_known.to_i
      if can_need > 0
        have = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level = 0').count
        if have < can_need
          class_spell_ids = SpellSource.where(source_type: 'Klass', source_id: @klass.id).pluck(:spell_id)
          cands = Spell.where(id: class_spell_ids, level: 0).where.not(id: SheetKnownSpell.where(sheet_klass_id: sk.id).select(:spell_id)).to_a
          cands.sample(can_need - have).each do |sp|
            SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sp.id)
          end
        end
      end
      # known spells (>0)
      if sc.spells_known
        need = sc.spells_known.to_i
        have = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level > 0').count
        if have < need
          class_spell_ids = SpellSource.where(source_type: 'Klass', source_id: @klass.id).pluck(:spell_id)
          gate_level = SpellRules.gate_for(@sheet, @klass)
          pool = Spell.where(id: class_spell_ids)
                      .where('level > 0 AND level <= ?', gate_level)
                      .where.not(id: SheetKnownSpell.where(sheet_klass_id: sk.id).select(:spell_id))
                      .to_a
          pool.sample(need - have).each do |sp|
            SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sp.id)
          end
        end
      end
    end

    @sheet.update!(metadata: meta)
  rescue => e
    Rails.logger.debug("ensure_level_requirements! skipped: #{e.message}")
  end
end
