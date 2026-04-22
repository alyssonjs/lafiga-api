module CharacterDraftSteps
  # Persists skill picks into both root selectedSkills (legacy) and
  # level1Choices (per-level canonical store).
  class SkillsStepService < BaseStepService
    def step_key = 'skills'

    protected

    def apply!(merged)
      if data.key?('selectedSkills')
        # ZS8 do segundo audit: `uniq` nao removia strings vazias, entao um item
        # como `''` ou `' '` (digitacao acidental ou bug do front) era
        # persistido. Filtro explicito por `present?` (apos strip).
        skills = Array(data['selectedSkills']).map { |s| s.to_s.strip }.reject(&:empty?).uniq
        validate_skills!(merged, skills)
        merged['selectedSkills'] = skills
        merged['level1Choices'] ||= {}
        merged['level1Choices']['skills'] = skills
      end
      if data.key?('expertise')
        exp = Array(data['expertise']).map { |s| s.to_s.strip }.reject(&:empty?).uniq
        validate_expertise!(merged, exp)
        merged['level1Choices'] ||= {}
        merged['level1Choices']['expertise'] = exp
      end
    end

    private

    # Gap G6.1 do relatorio de auditoria de steps: antes do fix, qualquer
    # string virava skill (ex.: 'Voar', 'Atletismo Plus', '<script>') era
    # aceita silenciosamente e gravada em `level1Choices.skills`. Resultado:
    # bug do front (digitar nome livre) ou cliente malicioso podia inflar
    # arrays. Agora validamos contra (a) catalogo da classe selecionada se
    # ela tiver `skill_proficiencies.options` em ClassRules; (b) count
    # maximo via `:choose`. Validacao e SOFT (warn!) em paridade com o
    # restante do BaseStepService — nao bloqueia, mas registra para
    # auditoria. O LevelUpGuardService faz o enforcement HARD no provision.
    def validate_skills!(merged, skills)
      class_id = merged.dig('selectedClass', 'id') || merged['_classId']
      return if class_id.blank? # sem classe selecionada, nada a validar

      rule = class_rule_for_id(class_id)
      return unless rule

      sp = rule[:skill_proficiencies]
      return unless sp.is_a?(Hash)

      max = sp[:choose].to_i
      if max.positive? && skills.size > max
        warn!("selectedSkills tem #{skills.size} skills, maximo permitido pela classe e #{max}")
      end

      options = sp[:options]
      # `:any` significa qualquer skill (ex.: Bardo) — pula validacao de catalogo.
      return if options == :any

      allowed = Array(options).map(&:to_s)
      return if allowed.empty?

      invalid = skills.reject { |s| allowed.include?(s) }
      warn!("selectedSkills contem skills fora do catalogo da classe: #{invalid.join(', ')}") if invalid.any?
    end

    # Gap G6.2 do relatorio de auditoria de steps: expertise so pode ser
    # aplicada em skills nas quais o personagem JA tem proficiencia
    # (regra do PHB para Bardo, Ladino, Sortudo). Antes nao validavamos:
    # cliente bugado podia gravar `expertise: ['Voar']` sem ter
    # 'Voar' em selectedSkills, e a UI exibia bonus dobrado num skill
    # inexistente. Agora warn! quando expertise nao e subset de
    # selectedSkills — enforcement HARD acontece no LevelUpGuardService
    # quando configurado (ver `expertise_skills.validate_subset`).
    def validate_expertise!(merged, expertise)
      return if expertise.empty?
      skills = Array(merged.dig('level1Choices', 'skills')) | Array(merged['selectedSkills'])
      skills = skills.map(&:to_s)
      orphan = expertise.reject { |e| skills.include?(e) }
      return if orphan.empty?

      warn!(
        "expertise contem skills sem proficiencia: #{orphan.join(', ')} " \
        '(expertise so e valida em skills com proficiencia)'
      )
    end

    def class_rule_for_id(class_id)
      api_index = nil
      numeric = class_id.to_s.match?(/\A\d+\z/)
      if numeric
        api_index = Klass.find_by(id: class_id.to_i)&.api_index
      else
        api_index = class_id.to_s
      end
      return nil if api_index.blank?
      ClassRules.find(api_index)
    rescue StandardError => e
      Rails.logger.warn "[SkillsStepService] ClassRules.find(#{api_index}) raised: #{e.class}: #{e.message}"
      nil
    end
  end
end
