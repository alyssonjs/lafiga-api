class LevelUpService
  prepend SimpleCommand

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

  def call
    ActiveRecord::Base.transaction do
      sk = @sheet.sheet_klasses.find_or_initialize_by(klass_id: @klass.id)
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

        # Persistir magias conhecidas escolhidas para este nível (se houver)
        Rails.logger.info "Calling persist_known_spells! for level #{new_level}"
        persist_known_spells!(sk, from_level: new_level, to_level: new_level)
        Rails.logger.info "persist_known_spells! completed for level #{new_level}"

        # HP ganho neste passo
        step_gain = if rolls.present? && rolls[i]
          rolls[i].to_i + con_mod
        else
          (hit_die / 2.0).ceil + con_mod
        end
        gained_hp += step_gain
      end

      # Aplicar total de HP acumulado
      @sheet.update!(hp_max: @sheet.hp_max + gained_hp, hp_current: [@sheet.hp_current + gained_hp, @sheet.hp_max + gained_hp].min)

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
      SubKlass.find_by!(api_index: str)
    end
  end

  def persist_known_spells!(sk, from_level:, to_level:)
    meta = @sheet.metadata || {}
    per = meta.dig('class_choices', 'per_level') || {}
    (from_level..to_level).each do |lvl|
      row = per[lvl.to_s] || {}
      # Persist explicit picks
      Array(row['cantrips']).each do |sp|
        sid = if sp.is_a?(Hash)
          (sp['id'] || sp[:id]).to_i
        elsif sp.is_a?(Numeric)
          sp.to_i
        else
          0
        end
        next if sid.zero?
        SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sid)
      end
      Array(row['spells']).each do |sp|
        sid = if sp.is_a?(Hash)
          (sp['id'] || sp[:id]).to_i
        elsif sp.is_a?(Numeric)
          sp.to_i
        else
          0
        end
        next if sid.zero?
        SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sid)
      end

      # Auto-preencher até o limite do nível (se faltando escolhas) para classes de magias conhecidas
      sc = SpellRules.sc_for(@klass, lvl)
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
          cands = pool.where('level > 0').to_a.select { |sp| SpellRules.can_learn_spell?(sk, sp) }
          cands.reject! { |sp| SheetKnownSpell.exists?(sheet_klass_id: sk.id, spell_id: sp.id) }
          cands.sample(need).each do |sp|
            SheetKnownSpell.find_or_create_by!(sheet_klass_id: sk.id, spell_id: sp.id)
            counts[:spells] += 1
          end
        end
      end
    end
  rescue => e
    Rails.logger.warn("Known spells persist skipped: #{e.message}")
  end

  # Best-effort auto-pick para evitar bloqueios triviais quando metadados existem mas escolhas faltam
  def ensure_level_requirements!(sk, current_level)
    meta = @sheet.metadata || {}
    meta['class_choices'] ||= {}
    meta['class_choices']['per_level'] ||= {}
    rule = ClassRules.find(@klass.api_index) || {}

    # 1) nível 1: perícias e instrumentos
    if current_level >= 1
      need_sk = rule.dig(:skill_proficiencies, :choose).to_i
      if need_sk > 0
        pick_src = (meta['class_choices']['skills_selected'] || meta['class_choices']['skills'] || [])
        arr = Array(pick_src).map { |x| x.is_a?(Hash) ? (x['name'] || x[:name]) : x }.compact
        if arr.size < need_sk
          options = if rule.dig(:skill_proficiencies, :options) == :any
                      ClassRules.dictionaries[:skills_all]
                    else
                      Array(rule.dig(:skill_proficiencies, :options))
                    end
          meta['class_choices']['skills_selected'] = options.sample(need_sk)
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
        list = case options
               when :invocations_core
                 ['Agonizing Blast','Armor of Shadows','Devil\'s Sight','Fiendish Vigor','Mask of Many Faces','Mire the Mind']
               else
                 Array(options)
               end
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
          pool = Spell.where(id: class_spell_ids).to_a.select { |sp| sp.level.to_i > 0 && SpellRules.can_learn_spell?(sk, sp) }
          pool.reject! { |sp| SheetKnownSpell.exists?(sheet_klass_id: sk.id, spell_id: sp.id) }
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
