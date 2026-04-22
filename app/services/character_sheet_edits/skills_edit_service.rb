module CharacterSheetEdits
  class SkillsEditService < BaseSheetEditService
    def step_key = 'skills'

    # Hierarquia de leitura para `selectedSkills`:
    #
    #   1. metadata.class_choices.per_level['1'].skills (fonte canônica do step)
    #   2. metadata.class_summary.skills (fallback do summary — escrito pelo
    #      provisioning canônico)
    #   3. sheet.class_summary['skills'] (coluna jsonb — última fonte da rake/seed)
    #
    # Antes só lia (1). Personagens criados antes do `SkillsEditService` existir
    # ou criados via fluxo de provisioning completo (que escreve só em (2)/(3))
    # voltavam vazios pelo per-step e o wizard de edição mostrava "Perícias"
    # incompleto após hard refresh — bug reportado.
    def read
      meta = (sheet.metadata || {})

      pl = meta.dig('class_choices', 'per_level', '1') || {}
      skills    = Array(pl['skills']).map(&:to_s)
      expertise = Array(pl['expertise']).map(&:to_s)

      if skills.empty?
        cs_meta = meta['class_summary'].is_a?(Hash) ? meta['class_summary'] : {}
        cs_col  = sheet.read_attribute(:class_summary)
        cs_col  = {} unless cs_col.is_a?(Hash)
        # union de ambas as fontes — espelha `build_proficiencies` do summary
        skills = (Array(cs_meta['skills']) | Array(cs_col['skills'])).map(&:to_s)
      end

      {
        'selectedSkills' => skills,
        'expertise'      => expertise
      }
    end

    protected

    def apply!
      meta = (sheet.metadata || {}).deep_stringify_keys
      meta['class_choices'] ||= {}
      meta['class_choices']['per_level'] ||= {}
      row1 = (meta['class_choices']['per_level']['1'] || {}).deep_dup

      if data.key?('selectedSkills')
        skills = Array(data['selectedSkills']).map(&:to_s).uniq
        validate_skills!(skills)
        row1['skills'] = skills
      end
      if data.key?('expertise')
        exp = Array(data['expertise']).map(&:to_s).uniq
        # Expertise valida contra a UNIAO das skills antigas + novas no MESMO
        # PATCH (cliente que envia `{selectedSkills: [...], expertise: [...]}`
        # atomicamente nao deveria pegar warn de orfa quando a skill nova
        # cobrir o expertise novo).
        skills_for_check = (row1['skills'] || []) | Array(data['selectedSkills']).map(&:to_s)
        validate_expertise!(exp, skills_for_check)
        row1['expertise'] = exp
      end

      meta['class_choices']['per_level']['1'] = row1
      sheet.metadata = meta
      sheet.save!

      # Replica o que `ClassEditService` e `ProgressionEditService` fazem:
      # mantém `sheet.class_summary` (coluna) e `metadata.class_summary` em sincronia
      # com a fonte canônica (`metadata.class_choices.per_level['1'].skills`). Sem
      # isso, `CharacterSheetSummaryService#build_proficiencies` lia `cs['skills']`
      # vazio e `proficiencies.skills.class` ficava `[]` no payload do summary,
      # mesmo com o metadata correto — o que reaparecia como "Perícias" cinza no
      # wizard de edição.
      ClassSummaryRebuilder.call(sheet)
    end

    private

    # Gap G6.1 do relatorio de auditoria de steps: paridade com
    # SkillsStepService — valida count e catalogo da classe via ClassRules.
    def validate_skills!(skills)
      sk = sheet.sheet_klasses.order(level: :asc).first
      return unless sk&.klass

      rule = ClassRules.find(sk.klass.api_index) rescue nil
      return unless rule.is_a?(Hash)

      sp = rule[:skill_proficiencies]
      return unless sp.is_a?(Hash)

      max = sp[:choose].to_i
      if max.positive? && skills.size > max
        warn!("selectedSkills tem #{skills.size} skills, maximo permitido pela classe e #{max}")
      end

      options = sp[:options]
      return if options == :any

      allowed = Array(options).map(&:to_s)
      return if allowed.empty?

      invalid = skills.reject { |s| allowed.include?(s) }
      warn!("selectedSkills contem skills fora do catalogo da classe: #{invalid.join(', ')}") if invalid.any?
    end

    # Gap G6.2: expertise so e valida em skills com proficiencia.
    def validate_expertise!(expertise, skills)
      return if expertise.empty?
      orphan = expertise.reject { |e| skills.include?(e) }
      return if orphan.empty?

      warn!(
        "expertise contem skills sem proficiencia: #{orphan.join(', ')} " \
        '(expertise so e valida em skills com proficiencia)'
      )
    end
  end
end
