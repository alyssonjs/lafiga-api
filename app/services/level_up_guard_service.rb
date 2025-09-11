class LevelUpGuardService
  prepend SimpleCommand

  # Ensures all requirements up to the current class level are fulfilled
  # before allowing progression to the next level.
  # Usage:
  #   LevelUpGuardService.call(sheet: sheet, klass: klass)
  # Fails with messages in Portuguese enumerating the missing items.
  def initialize(sheet:, klass:)
    @sheet = sheet
    @klass = klass
  end

  def call
    sk = @sheet.sheet_klasses.find_by(klass_id: @klass.id)
    return true unless sk

    current_level = sk.level.to_i
    return true if current_level <= 0 # nothing to check

    rule = safely_find_class_rule(@klass)
    missing = []

    # 1) Subclasse obrigatória se atingiu o nível de escolha
    threshold = @klass.try(:subclass_level).to_i
    if threshold > 0 && current_level >= threshold && sk.sub_klass_id.blank?
      # Verificar se há uma subclasse sendo definida no metadata
      meta = @sheet.metadata || {}
      meta_choice = meta.dig('class_choices', 'subclass_id')
      if meta_choice.blank?
        missing << "Subclasse obrigatória a partir do nível #{threshold} ainda não escolhida"
      else
        Rails.logger.info "Subclasse obrigatória será definida via metadata: #{meta_choice}"
        # Se há uma subclasse no metadata, não considerar como erro
        # O LevelUpService irá aplicá-la
      end
    end

    # 2) Escolhas obrigatórias por nível, conforme ClassRules
    per_required = (rule[:required_choices_at_level] || {})
    meta = @sheet.metadata || {}
    per = meta.dig('class_choices', 'per_level') || {}
    (1..current_level).each do |lvl|
      next unless per_required[lvl].present?
      per_required[lvl].each do |key, conf|
        # prefer per-level pick, but fallback to top-level class_choices[key]
        top = (meta.dig('class_choices') || {})[key.to_s]
        chosen = (per[lvl.to_s] || {})[key.to_s]
        chosen = top if (chosen.nil? || (chosen.respond_to?(:empty?) && chosen.empty?)) && top.present?
        need = conf[:choose].to_i
        
        # Se não há escolha feita, tentar fazer escolha automática
        if chosen.blank? || (chosen.respond_to?(:empty?) && chosen.empty?)
          Rails.logger.info "Fazendo escolha automática para #{key} no nível #{lvl}"
          auto_choice = make_auto_choice(key, conf, meta)
          if auto_choice.present?
            chosen = auto_choice
            # Atualizar metadata com a escolha automática
            if meta['class_choices'].nil?
              meta['class_choices'] = {}
            end
            meta['class_choices'][key.to_s] = chosen
            Rails.logger.info "Escolha automática feita e salva: #{chosen}"
          end
        end
        
        if need <= 1
          if chosen.blank?
            missing << "Falta escolher #{humanize_choice(key)} no nível #{lvl}"
          end
        else
          arr = Array(chosen)
          if arr.size < need
            missing << "Faltam #{need - arr.size} de #{need} escolhas de #{humanize_choice(key)} no nível #{lvl}"
          end
        end
      end
    end

    # 3) Habilidades/Perícias iniciais da classe (nível 1)
    if current_level >= 1
      need_sk = rule.dig(:skill_proficiencies, :choose).to_i
      if need_sk > 0
        raw_sk = (meta.dig('class_choices', 'skills_selected') || meta.dig('class_choices', 'skills') || [])
        chosen_sk = Array(raw_sk).map { |x| x.is_a?(Hash) ? x['name'] || x[:name] : x }.compact
        if chosen_sk.size < need_sk
          missing << "Selecione #{need_sk} perícias da classe (restam #{need_sk - chosen_sk.size})"
        end
      end
      # Instrumentos (ex.: Bardo)
      tp = rule[:tool_proficiencies]
      inst_conf = tp.is_a?(Hash) ? tp[:instruments] : nil
      inst_need = inst_conf.is_a?(Hash) ? inst_conf[:choose].to_i : 0
      if inst_need > 0
        raw_inst = (meta.dig('class_choices', 'instruments_selected') || meta.dig('class_choices', 'instruments') || [])
        chosen = Array(raw_inst).map { |x| x.is_a?(Hash) ? x['name'] || x[:name] : x }.compact
        if chosen.size < inst_need
          missing << "Selecione #{inst_need} instrumento(s) (restam #{inst_need - chosen.size})"
        end
      end
    end

    # 4) Background (tratar como obrigatório para avançar)
    if current_level >= 1
      bg = meta['background_summary']
      # aceitar fallback de meta.background simples
      if (bg.blank? || bg['key'].blank?) && (meta['background'].to_s.strip.empty?)
        missing << 'Background não definido na ficha'
      elsif bg.present?
        # Verificação mínima de proficiências do background
        begin
          bg_rule = BackgroundRules.find(bg['key'])
          if bg_rule
            # Skills do background devem existir e bater com o mínimo
            need = Array(bg_rule[:skills]).size
            chosen_sk = Array(bg['skills'])
            if chosen_sk.size < need
              missing << "Background incompleto: defina #{need} perícias (restam #{need - chosen_sk.size})"
            end
          end
        rescue NameError
          # BackgroundRules não instalado; considera-se apenas presença
        end
      end
    end

    # 5) Magias/Cantrips exigidos por nível para classes de magias conhecidas
    sc = SpellRules.sc_for(@klass, current_level)
    Rails.logger.info "SpellRules.sc_for(#{@klass.api_index}, #{current_level}) = #{sc.present? ? 'found' : 'not found'}"
    if sc
      known_limit = sc.spells_known
      cantrips_limit = sc.cantrips_known
      Rails.logger.info "Spell limits: known=#{known_limit}, cantrips=#{cantrips_limit}"
      if known_limit
        known_count = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level > 0').count
        Rails.logger.info "Known spells count: #{known_count}/#{known_limit}"
        if known_count < known_limit.to_i
          missing << "Magias conhecidas: selecione #{known_limit} (restam #{known_limit.to_i - known_count})"
        end
      end
      if cantrips_limit
        cantrip_count = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level = 0').count
        Rails.logger.info "Cantrips count: #{cantrip_count}/#{cantrips_limit}"
        if cantrip_count < cantrips_limit.to_i
          missing << "Truques (cantrips): selecione #{cantrips_limit} (restam #{cantrips_limit.to_i - cantrip_count})"
        end
      end
    end

    if missing.any?
      Rails.logger.warn "LevelUpGuardService failed for level #{current_level}: #{missing.join('; ')}"
      missing.each { |m| errors.add(:base, m) }
      return false
    end

    Rails.logger.info "LevelUpGuardService passed for level #{current_level}"
    true
  end

  private

  def safely_find_class_rule(klass)
    begin
      rule = ClassRules.find(klass.api_index) || {}
      Rails.logger.info "ClassRules.find(#{klass.api_index}) = #{rule.present? ? 'found' : 'not found'}"
      rule.with_indifferent_access
    rescue NameError => e
      Rails.logger.warn "ClassRules not available: #{e.message}"
      {}.with_indifferent_access
    end
  end

  def make_auto_choice(key, config, meta)
    choose_count = config[:choose].to_i
    options = config[:options]
    
    case key.to_s
    when 'expertise_skills'
      available_skills = meta.dig('class_choices', 'skills_selected') || []
      if available_skills.length >= choose_count
        available_skills.first(choose_count)
      else
        ['Furtividade', 'Percepção'].first(choose_count)
      end
    when 'fighting_style'
      if options.is_a?(Array) && options.any?
        options.first
      else
        'Duelo'
      end
    when 'metamagic'
      if options.is_a?(Array) && options.length >= choose_count
        options.first(choose_count)
      else
        ['Acelerar Magia', 'Expandir Magia'].first(choose_count)
      end
    when 'invocations'
      ['Visão do Diabo', 'Maldição de Eldritch'].first(choose_count)
    when 'pact_boon'
      'Pacto do Tomo'
    else
      nil
    end
  end

  def humanize_choice(key)
    case key.to_s
    when 'fighting_style' then 'Estilo de Luta'
    when 'expertise_skills' then 'Perícias de Expertise'
    when 'metamagic' then 'Metamágicas'
    when 'invocations' then 'Invocações'
    when 'pact_boon' then 'Pacto'
    else key.to_s.tr('_', ' ')
    end
  end
end
