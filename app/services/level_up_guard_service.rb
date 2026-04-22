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

  # Kit 1.fix-autochoice: gate global p/ enforcement de required_choices.
  # Quando true, NÃO preenche silenciosamente (warn + missing).
  #
  # Precedência:
  #   1. ENV LAFIGA_STRICT_REQUIRED_CHOICES=true|false   (override per-process)
  #   2. defined?(RSpec)                                  (default seguro nos specs)
  #   3. Rails.application.config.x.lafiga                (dev/prod via initializer)
  #
  # NOTA: o container do projeto roda com RAILS_ENV=development mesmo durante
  # rspec (ENV vem setado antes do rails_helper.rb conseguir forçar 'test'),
  # por isso `Rails.env.test?` não é confiável aqui — usamos `defined?(RSpec)`.
  def self.strict_required_choices?
    explicit = ENV['LAFIGA_STRICT_REQUIRED_CHOICES']
    return explicit.to_s.downcase == 'true' if explicit.present?
    return true if defined?(RSpec)
    cfg = Rails.application.config.x.lafiga&.strict_required_choices
    cfg == true
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
        
        # Kit 1.fix-autochoice: emite warn SEMPRE que cairia em auto-fill
        # (visibilidade para auditoria, mesmo em modo non-strict).
        # Em strict, NÃO preenche → guard reporta missing corretamente.
        if chosen.blank? || (chosen.respond_to?(:empty?) && chosen.empty?)
          Rails.logger.warn(
            "[autochoice-guard] would-have-filled key=#{key} klass=#{@klass.api_index} level=#{lvl} strict=#{self.class.strict_required_choices?}"
          )
          unless self.class.strict_required_choices?
            auto_choice = make_auto_choice(key, conf, meta)
            if auto_choice.present?
              chosen = auto_choice
              meta['class_choices'] ||= {}
              meta['class_choices'][key.to_s] = chosen
              Rails.logger.info "Escolha automática feita e salva: #{chosen}"
            end
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

        # Kit 3: subset validation (opt-in via `validate_subset: true` na regra).
        # Confirma que cada item escolhido pertence ao catálogo de options.
        # Suporta options como Symbol (resolve via ClassRules.dictionaries),
        # Array<String> (legacy) ou Array<Hash> (com slug/name).
        if conf[:validate_subset] && chosen.present?
          allowed_ids = resolve_subset_options(conf[:options])
          unless allowed_ids.empty?
            chosen_ids = Array(chosen).map { |x| extract_choice_id(x) }.compact
            invalid = chosen_ids.reject { |c| allowed_ids.include?(c) }
            if invalid.any?
              missing << "#{humanize_choice(key)} no nível #{lvl}: opção(ões) inválida(s) [#{invalid.join(', ')}]. Permitidas: #{allowed_ids.join(', ')}"
            end
          end
        end
      end
    end

    # 3) Habilidades/Perícias iniciais da classe (nível 1)
    if current_level >= 1
      need_sk = rule.dig(:skill_proficiencies, :choose).to_i
      if need_sk > 0
        # per_level['1'].skills é a fonte canónica vinda do wizard;
        # caímos para os campos root só quando per_level estiver vazio.
        per_lvl1_sk = meta.dig('class_choices', 'per_level', '1', 'skills') || []
        raw_sk = per_lvl1_sk.presence || meta.dig('class_choices', 'skills_selected') || meta.dig('class_choices', 'skills') || []
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

    # 4) Background
    # Observação: relaxamos o bloqueio de subida de nível por ausência de background
    # para permitir criações programáticas de ficha/classe em lote. Mantemos apenas logs.
    if current_level >= 1
      bg = meta['background_summary']
      if (bg.blank? || bg['key'].blank?) && (meta['background'].to_s.strip.empty?)
        Rails.logger.warn 'LevelUpGuardService: Background ausente; prosseguindo mesmo assim.'
      elsif bg.present?
        begin
          bg_rule = BackgroundRules.find(bg['key'])
          if bg_rule
            need = Array(bg_rule[:skills]).size
            chosen_sk = Array(bg['skills'])
            if chosen_sk.size < need
              Rails.logger.warn "LevelUpGuardService: Background incompleto (skills #{chosen_sk.size}/#{need}); prosseguindo."
            end
          end
        rescue NameError
          # Sem catálogo de background, não abortar
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

    # 6) Bruxo: validar Invocações (pré‑requisitos e limite por nível)
    if @klass.api_index.to_s == 'warlock'
      begin
        rule = safely_find_class_rule(@klass)
        allowed = begin
          (rule.dig(:feature_rules, :eldritch_invocations, :count_by_level) || {})[current_level] || 0
        rescue
          0
        end
        meta = @sheet.metadata || {}
        per = meta.dig('class_choices','per_level') || {}
        # Agregar invocações escolhidas até o nível atual (apenas per_level; ignorar topo para evitar duplicidade)
        chosen_inv = []
        (1..current_level).each do |lvl|
          row = per[lvl.to_s] || {}
          invs = row['invocations'] || row[:invocations]
          Array(invs).each { |x| chosen_inv << (x.is_a?(Hash) ? (x['name'] || x[:name] || x['id'] || x[:id]) : x) }
        end
        chosen_inv = chosen_inv.compact.map(&:to_s).map(&:strip).uniq

        if allowed.to_i > 0 && chosen_inv.size > allowed.to_i
          missing << "Invocações: selecionadas #{chosen_inv.size}, máximo #{allowed} para o nível atual"
        end

        # Kit 1.invocations: prereqs vêm do catálogo canônico (eldritch_invocations.yml)
        # ao invés de hardcoded aqui. Mantém retrocompat aceitando slug/name_pt/name_en/alias.
        # Schema dos prereqs: { level:, pact:, spell:, blast: } (chaves opcionais).

        # Boon escolhido
        pact_boon = begin
          # Prefer top‑level
          b = meta.dig('class_choices','pact_boon')
          unless b
            (1..current_level).each do |lvl|
              row = per[lvl.to_s] || {}
              b ||= row['pact_boon'] || row[:pact_boon]
              break if b
            end
          end
          b = (b.is_a?(Hash) ? (b['name'] || b[:name] || b['id'] || b[:id]) : b)
          (b || '').to_s.downcase
        rescue
          ''
        end

        # Eldritch Blast conhecido?
        has_blast = begin
          blast = Spell.find_by(name: 'Eldritch Blast')
          if blast
            SheetKnownSpell.joins(:sheet_klass).where(sheet_klasses: { sheet_id: @sheet.id }).where(spell_id: blast.id).exists?
          else
            # Fallback: verificar metadata por nome (inclui PT)
            names = ['Eldritch Blast','Rajada Mística','Rajada Mistica']
            found = false
            (1..current_level).each do |lvl|
              row = per[lvl.to_s] || {}
              [row['cantrips'], row['spells'], row['learn_any_class_spells']].each do |arr|
                Array(arr).each do |x|
                  nm = (x.is_a?(Hash) ? (x['name'] || x[:name] || x['id'] || x[:id]) : x)
                  if nm && names.include?(nm.to_s)
                    found = true
                    break
                  end
                end
                break if found
              end
              break if found
            end
            found
          end
        rescue
          false
        end

        chosen_inv.each do |identifier|
          entry = begin
            ClassChoicesCatalog.resolve(:eldritch_invocations, identifier)
          rescue StandardError => e
            Rails.logger.warn "Invocação não encontrada no catálogo: #{identifier} (#{e.message})"
            nil
          end
          next unless entry

          req = entry[:prereqs] || {}
          display = entry[:name_pt] || identifier

          # spell: 'Eldritch Blast' OU blast: true (legado)
          needs_blast = req['blast'] || req[:blast] ||
                        (req['spell'] || req[:spell]).to_s.casecmp?('Eldritch Blast')
          if needs_blast && !has_blast
            missing << "Invocação #{display} requer o truque Eldritch Blast"
          end

          if (need = (req['pact'] || req[:pact]))
            need_str = need.to_s
            ok = case need_str
                 when 'tome'  then pact_boon.include?('tomo')
                 when 'blade' then pact_boon.include?('lâmina') || pact_boon.include?('lamina')
                 when 'chain' then pact_boon.include?('corrente')
                 else false
                 end
            missing << "Invocação #{display} requer Pacto do #{need_str.capitalize}" unless ok
          end

          min_level = (req['level'] || req[:level]).to_i
          if min_level > 0 && current_level < min_level
            missing << "Invocação #{display} requer nível #{min_level} de Bruxo"
          end
        end
      rescue => e
        Rails.logger.warn "Falha ao validar invocações: #{e.message}"
      end
    end

    # 7) Fighter Battle Master: validar Manobras (catálogo + count by level)
    # Kit 1.maneuvers — count by level vem da progressão BM (3/7/10/15).
    # Subclass identificada via SheetKlass.sub_klass_id OU metadata.class_choices.subclass_id.
    if @klass.api_index.to_s == 'fighter'
      begin
        subclass_api = (sk.sub_klass&.api_index ||
                        @sheet.metadata.to_h.dig('class_choices', 'subclass_id') ||
                        '').to_s.downcase
        if subclass_api == 'battlemaster'
          # Count by level (PHB Battle Master): 3→3, 7→5, 10→7, 15→9
          allowed = case current_level
                    when 0..2 then 0
                    when 3..6 then 3
                    when 7..9 then 5
                    when 10..14 then 7
                    else 9
                    end

          meta = @sheet.metadata || {}
          per = meta.dig('class_choices', 'per_level') || {}
          chosen_man = []
          (1..current_level).each do |lvl|
            row = per[lvl.to_s] || {}
            mans = row['maneuvers'] || row[:maneuvers]
            Array(mans).each { |x| chosen_man << (x.is_a?(Hash) ? (x['slug'] || x[:slug] || x['name'] || x[:name]) : x) }
          end
          chosen_man = chosen_man.compact.map(&:to_s).map(&:strip).uniq

          if allowed > 0 && chosen_man.size > allowed
            missing << "Manobras: selecionadas #{chosen_man.size}, máximo #{allowed} para o nível atual (Battle Master)"
          end

          # Validar subset via catálogo (toda manobra deve existir).
          chosen_man.each do |identifier|
            entry = ClassChoicesCatalog.resolve(:maneuvers, identifier)
            unless entry
              missing << "Manobra desconhecida: #{identifier} (não consta no catálogo canônico)"
            end
          end
        end
      rescue => e
        Rails.logger.warn "Falha ao validar manobras: #{e.message}"
      end
    end

    # 8) Monk Way of the Four Elements: validar Disciplinas (catálogo + count + level prereq)
    # Kit 1.disciplines — count by level (PHB Four Elements): 3→1, 6→2, 11→3, 17→4.
    if @klass.api_index.to_s == 'monk'
      begin
        subclass_api = (sk.sub_klass&.api_index ||
                        @sheet.metadata.to_h.dig('class_choices', 'subclass_id') ||
                        '').to_s.downcase
        if subclass_api == 'four_elements'
          allowed = case current_level
                    when 0..2 then 0
                    when 3..5 then 1
                    when 6..10 then 2
                    when 11..16 then 3
                    else 4
                    end

          meta = @sheet.metadata || {}
          per = meta.dig('class_choices', 'per_level') || {}
          chosen_disc = []
          (1..current_level).each do |lvl|
            row = per[lvl.to_s] || {}
            ds = row['disciplines'] || row[:disciplines] ||
                 row['elemental_disciplines'] || row[:elemental_disciplines]
            Array(ds).each { |x| chosen_disc << (x.is_a?(Hash) ? (x['slug'] || x[:slug] || x['name'] || x[:name]) : x) }
          end
          chosen_disc = chosen_disc.compact.map(&:to_s).map(&:strip).uniq

          if allowed > 0 && chosen_disc.size > allowed
            missing << "Disciplinas: selecionadas #{chosen_disc.size}, máximo #{allowed} para o nível atual (Quatro Elementos)"
          end

          # Validar subset + prereq de nível via catálogo.
          chosen_disc.each do |identifier|
            entry = ClassChoicesCatalog.resolve(:elemental_disciplines, identifier)
            unless entry
              missing << "Disciplina desconhecida: #{identifier} (não consta no catálogo canônico)"
              next
            end
            req_level = (entry[:prereqs] || {}).then { |p| (p['level'] || p[:level]).to_i }
            if req_level > 0 && current_level < req_level
              display = entry[:name_pt] || identifier
              missing << "Disciplina #{display} requer nível #{req_level} de Monge"
            end
          end
        end
      rescue => e
        Rails.logger.warn "Falha ao validar disciplinas: #{e.message}"
      end
    end

    # 9) Cozinheiro: validar Petiscos (catálogo + count + level/subclass prereqs)
    # Kit 1.snacks — count by level vem de feature_rules.cook.snacks.known_by_level
    # (1=>3, 2=>3, 3=>4, ...). Subclass gating é feito via prereqs.subclass do
    # catálogo. A subclasse é escolhida no nv 3 — antes disso só petiscos base.
    if @klass.api_index.to_s == 'cozinheiro'
      begin
        known_table = (@klass.respond_to?(:rules) ? @klass.rules : nil) ||
                      ClassRules::CLASS_RULES.dig(:cozinheiro, :feature_rules, 'cook', 'snacks', 'known_by_level') ||
                      ClassRules::CLASS_RULES.dig('cozinheiro', 'feature_rules', 'cook', 'snacks', 'known_by_level') ||
                      {}
        allowed = known_table[current_level] || known_table[current_level.to_s] || 0

        meta = @sheet.metadata || {}
        per = meta.dig('class_choices', 'per_level') || {}
        chosen_snacks = []
        (1..current_level).each do |lvl|
          row = per[lvl.to_s] || {}
          ss = row['snacks'] || row[:snacks]
          Array(ss).each { |x| chosen_snacks << (x.is_a?(Hash) ? (x['slug'] || x[:slug] || x['name'] || x[:name]) : x) }
        end
        chosen_snacks = chosen_snacks.compact.map(&:to_s).map(&:strip).uniq

        if allowed > 0 && chosen_snacks.size > allowed
          missing << "Petiscos: selecionados #{chosen_snacks.size}, máximo #{allowed} para o nível atual (Cozinheiro)"
        end

        # Subclass api_index do char (escolhida a partir do nv 3).
        subclass_api = (sk.sub_klass&.api_index ||
                        @sheet.metadata.to_h.dig('class_choices', 'subclass_id') ||
                        '').to_s

        chosen_snacks.each do |identifier|
          entry = ClassChoicesCatalog.resolve(:snacks, identifier)
          unless entry
            missing << "Petisco desconhecido: #{identifier} (não consta no catálogo canônico)"
            next
          end
          pr = entry[:prereqs] || {}
          req_level = (pr['level'] || pr[:level]).to_i
          if req_level > 0 && current_level < req_level
            display = entry[:name_pt] || identifier
            missing << "Petisco #{display} requer nível #{req_level} de Cozinheiro"
          end
          req_sub = pr['subclass'] || pr[:subclass]
          if req_sub.present? && req_sub.to_s != subclass_api
            display = entry[:name_pt] || identifier
            missing << "Petisco #{display} requer subclasse #{req_sub} (atual: #{subclass_api.presence || 'nenhuma'})"
          end
        end
      rescue => e
        Rails.logger.warn "Falha ao validar petiscos: #{e.message}"
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

  # Kit 3: resolve `options` (Symbol/Array) para uma lista de identificadores
  # canônicos contra os quais escolhas são validadas.
  #
  # Aceita:
  #   - Symbol  → busca em ClassRules.dictionaries[sym]
  #   - String  → wraps em [string]
  #   - Array<String> → retorna as is (legacy)
  #   - Array<Hash>   → extrai 'slug' || 'name' || 'id' de cada hash (novo)
  #   - nil/outros    → []
  def resolve_subset_options(options)
    # Symbol → tenta ClassChoicesCatalog primeiro (formato novo com slug+aliases),
    # fallback pra dictionaries (formato legado Array<String>).
    if options.is_a?(Symbol)
      begin
        if defined?(ClassChoicesCatalog) && File.exist?(File.join(ClassChoicesCatalog::CONFIG_DIR, "#{options}.yml"))
          # acceptable_identifiers inclui slug + name_pt + name_en + aliases
          # → tolerância máxima durante a transição (chars com nomes legados continuam OK)
          return ClassChoicesCatalog.acceptable_identifiers(options).map(&:to_s)
        end
      rescue ClassChoicesCatalog::SchemaError => e
        Rails.logger.warn "ClassChoicesCatalog falhou ao carregar :#{options}: #{e.message}"
      rescue NameError
        # ClassChoicesCatalog não definido ainda
      end

      list = begin
        ClassRules.dictionaries[options] || []
      rescue NameError
        []
      end
    else
      list = case options
             when String then [options]
             when Array  then options
             else []
             end
    end

    Array(list).map { |item|
      if item.is_a?(Hash)
        h = item.transform_keys(&:to_s)
        h['slug'] || h['name'] || h['name_pt'] || h['id']
      else
        item.to_s
      end
    }.compact.map(&:to_s)
  end

  # Extrai o identificador comparável de uma escolha feita pelo player
  # (pode vir como String, Hash com :name/:id/:slug, ou objeto).
  def extract_choice_id(choice)
    if choice.is_a?(Hash)
      h = choice.transform_keys(&:to_s)
      (h['slug'] || h['name'] || h['name_pt'] || h['id']).to_s
    else
      choice.to_s
    end
  end
end
