class Api::V1::Admin::SpellsController < ApplicationController
  # Compendio / editor de magias: mesmos mestres que itens magicos (DM site-wide + Admin).
  # `authorize_admin_request` barrava DM e o front recebia 401 (apiClient limpava sessao).
  before_action :authorize_site_wide_dm
  before_action :set_spell, only: [:show, :update, :destroy, :add_source, :remove_source]

  def index
    scope = Spell.all
    scope = scope.where(level: params[:level].to_i)        if params[:level].present?
    scope = scope.where(school: params[:school])           if params[:school].present?
    if params[:q].present?
      q = "%#{params[:q].to_s.downcase}%"
      scope = scope.where('LOWER(name) LIKE :q OR LOWER(api_index) LIKE :q', q: q)
    end
    scope = scope.order(:level, :name).limit(1000)
    rows = scope.to_a
    idx_map = Spell.klass_api_indexes_by_spell_id(rows.map(&:id))
    spells_json = rows.map do |s|
      s.as_json(except: [:created_at, :updated_at]).merge('klass_api_indexes' => idx_map[s.id] || [])
    end
    render json: { spells: spells_json }, status: :ok
  end

  def show
    idx = Spell.klass_api_indexes_by_spell_id([@spell.id])[@spell.id] || []
    render json: {
      spell: @spell.as_json(except: [:created_at, :updated_at]).merge('klass_api_indexes' => idx),
      sources: atrelagens_json(@spell)
    }, status: :ok
  end

  # GET /api/v1/admin/spells/source_options
  #
  # As fontes que EXISTEM, para o seletor encadeado. Espelha o
  # `proficiencies#source_options`, com três diferenças que importam:
  #
  #   1. devolve `id`, não `api_index` — `spell_sources.source_id` é um id;
  #   2. `Feature` tem TRÊS níveis (classe → subclasse → feature), porque uma
  #      feature solta no meio de 1301 seria impossível de escolher;
  #   3. ⚠️ `Klass` NÃO entra. As atrelagens de classe já têm dono: o seletor
  #      "Classes" do formulário da magia, que faz replace-all via
  #      `sync_klass_spell_sources!`. Medido: atrelar uma classe por aqui e
  #      salvar a magia a seguir APAGA a atrelagem em silêncio. Oferecer os
  #      dois caminhos seria construir o mecanismo paralelo que este projeto já
  #      pagou caro noutras áreas.
  def source_options
    render json: {
      Race: Race.order(:name).map { |r|
        { key: r.id, name: r.name,
          children: SubRace.where(race_id: r.id).order(:name).map { |sr| { key: sr.id, name: sr.name } } }
      },
      SubKlass: Klass.order(:name).map { |k|
        { key: k.id, name: k.name,
          children: SubKlass.where(klass_id: k.id).order(:name).map { |sk| { key: sk.id, name: sk.name } } }
      },
      Feature: opcoes_de_feature,
      Feat: Feat.order(:name).map { |f| { key: f.id, name: f.name } },
      Background: Background.order(:name).map { |b| { key: b.id, name: b.name } }
    }, status: :ok
  end

  # POST /api/v1/admin/spells/:id/sources
  #
  # ⚠️ Entra sempre como `manual`: `derived` é território dos rakes, e um
  # re-semear apagaria o que fosse marcado assim por engano. Mesma regra das
  # proficiências.
  def add_source
    attrs = params.require(:source).permit(
      :source_type, :source_id, :casting_mode, :grant_mode, :choose_count,
      :uses_per_long_rest, :uses_per_short_rest, :resource_key, :resource_cost,
      :min_character_level, :min_class_level, :always_prepared, :ability_override, :notes
    )

    if attrs[:source_type].to_s == 'Klass'
      return render(json: {
        errors: ['Atrelagem de CLASSE é feita no seletor "Classes" do formulário da magia — ' \
                 'gravar por aqui seria apagado no próximo salvamento.']
      }, status: :unprocessable_entity)
    end
    return render(json: { errors: ['fonte não encontrada'] }, status: :unprocessable_entity) unless fonte_existe?(attrs)

    # ⚠️ Tira nil e string vazia, mas NÃO `false`: `compact_blank` (Rails 6.1)
    # não existe aqui, e `blank?` engoliria `always_prepared: false`.
    limpos = attrs.to_h.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
    src = SpellSource.new(limpos.merge(spell_id: @spell.id, origin: 'manual'))
    if src.save
      render json: { source: atrelagem_json(src) }, status: :created
    else
      render json: { errors: src.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/spells/:id/sources/:source_id
  #
  # ⚠️ Apagar uma DERIVADA é inútil sozinho: o próximo seed a traz de volta,
  # porque ela reflete o que a fonte real declara. A resposta diz isso em vez de
  # deixar o mestre a achar que resolveu.
  def remove_source
    src = SpellSource.find_by(id: params[:source_id], spell_id: @spell.id)
    return render(json: { errors: 'source not found' }, status: :not_found) unless src

    derivada = src.origin == 'derived'
    era_classe = src.source_type == 'Klass'
    src.destroy
    render json: {
      removed: true,
      warning: if era_classe then 'klass_belongs_to_form'
               elsif derivada then 'derived_will_return'
               end
    }.compact, status: :ok
  end

  def create
    attrs = permitted
    @spell = Spell.new(attrs)
    @spell.api_index = derive_api_index(@spell) if @spell.api_index.blank?
    if @spell.api_index.blank?
      render json: { errors: ['name e obrigatorio para gerar o api_index'] }, status: :unprocessable_entity
      return
    end
    unless @spell.save
      render json: { errors: @spell.errors.full_messages }, status: :unprocessable_entity
      return
    end

    indexes_param = spell_klass_api_indexes_param
    if indexes_param != :missing
      begin
        sync_klass_spell_sources!(@spell, indexes_param)
      rescue ArgumentError => e
        @spell.destroy
        render json: { errors: [e.message] }, status: :unprocessable_entity
        return
      end
    end

    render json: { spell: admin_spell_json(@spell) }, status: :created
  end

  def update
    indexes_param = spell_klass_api_indexes_param
    unless @spell.update(permitted)
      render json: { errors: @spell.errors.full_messages }, status: :unprocessable_entity
      return
    end

    if indexes_param != :missing
      begin
        sync_klass_spell_sources!(@spell, indexes_param)
      rescue ArgumentError => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
        return
      end
    end

    render json: { spell: admin_spell_json(@spell) }, status: :ok
  end

  # DELETE /api/v1/admin/spells/:id
  #
  # Query `force=true`: remove SheetKnownSpell / SheetPreparedSpell, limpa tokens em
  # metadata (spell_selections + class_choices.per_level), apaga SpellSource e a Spell.
  # Sem `force`, 422 se ainda houver linhas em fichas.
  def destroy
    force = ActiveModel::Type::Boolean.new.cast(params[:force])
    known_n = SheetKnownSpell.where(spell_id: @spell.id).count
    prep_n = SheetPreparedSpell.where(spell_id: @spell.id).count

    if !force && (known_n.positive? || prep_n.positive?)
      render json: {
        error: 'spell_on_sheets',
        message: 'Magia ainda esta em uma ou mais fichas (conhecidas ou preparadas). Marque a opção para remover das fichas no grimório ou limpe manualmente.',
        sheet_known_spells: known_n,
        sheet_prepared_spells: prep_n,
        force_param: 'force=true'
      }, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      if force && (known_n.positive? || prep_n.positive?)
        Admin::SpellForceDeletePurgeService.new(@spell).call
      end
      SheetKnownSpell.where(spell_id: @spell.id).delete_all
      SheetPreparedSpell.where(spell_id: @spell.id).delete_all
      SpellSource.where(spell_id: @spell.id).delete_all
      @spell.destroy!
    end
    head :no_content
  rescue ActiveRecord::RecordNotDestroyed
    render json: { errors: @spell.errors.full_messages.presence || ['nao foi possivel apagar a magia'] },
           status: :unprocessable_entity
  end

  private

  def set_spell
    @spell = Spell.find_by(api_index: params[:id]) || Spell.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Spell not found' }, status: :not_found
  end

  # Estrutura mecânica do combat_data (Open5e/editor). Chaves dinâmicas (upcast /
  # cantrip_scaling têm níveis como chave) usam `{}` = hash de escalares arbitrário.
  COMBAT_DATA_PERMIT = [
    :source, :resolution, :save_ability, :save_success,
    :range_ft, :target_count, :target_count_per_slot, :concentration, :ritual,
    { target_count_cantrip_scaling: {} },
    { damage: [:dice, { types: [], upcast: {}, cantrip_scaling: {} }] },
    { area: [:shape, :size_ft] },
    { duration: [:text, :rounds] },
    { components: [:v, :s, :m, :consumed] },
    { inflicts_conditions: [:key, :polarity, :save, :repeat_save] },
    { removes_conditions: [] }
  ].freeze

  def permitted
    attrs = params.require(:spell).permit(
      :api_index, :name, :level, :school, :range,
      :components, :material, :ritual, :duration,
      :concentration, :casting_time, :desc, :higher_level,
      combat_data: COMBAT_DATA_PERMIT
    )
    # jsonb exige Hash puro; ActionController::Parameters (mesmo permitido) seria
    # serializado com artefatos. `to_h` do permitido devolve só as chaves liberadas.
    attrs[:combat_data] = attrs[:combat_data].to_h if attrs.key?(:combat_data)
    attrs
  end

  # :missing = cliente nao enviou campo (nao altera SpellSource Klass)
  def spell_klass_api_indexes_param
    raw_spell = params[:spell]
    return :missing if raw_spell.blank?

    h = raw_spell.respond_to?(:to_unsafe_h) ? raw_spell.to_unsafe_h : raw_spell
    key_present = h.key?('klass_api_indexes') || h.key?(:klass_api_indexes)
    return :missing unless key_present

    raw = h['klass_api_indexes'] || h[:klass_api_indexes]
    Array(raw).map { |x| x.to_s.downcase.strip }.reject(&:blank?).uniq
  end

  def sync_klass_spell_sources!(spell, api_indexes)
    wanted = Array(api_indexes).map { |x| x.to_s.downcase.strip }.reject(&:blank?).uniq
    rows = Klass.where(api_index: wanted).to_a
    found = rows.map(&:api_index)
    unknown = wanted - found
    raise ArgumentError, "Classes desconhecidas: #{unknown.join(', ')}" if unknown.any?

    klass_ids = rows.map(&:id)
    SpellSource.where(source_type: 'Klass', spell_id: spell.id).where.not(source_id: klass_ids).delete_all
    klass_ids.each do |kid|
      SpellSource.find_or_create_by!(source_type: 'Klass', source_id: kid, spell_id: spell.id) do |ss|
        ss.always_prepared = false
      end
    end
  end

  # Classe → (features da própria classe | subclasse) → feature.
  #
  # ⚠️ O nível do meio mistura duas coisas de propósito: as 307 features de
  # CLASSE penduram em `class_levels` e as 994 de SUBCLASSE em
  # `sub_klass_levels`. Sem a entrada sintética "features da classe", as de
  # classe ficariam inalcançáveis pelo seletor.
  def opcoes_de_feature
    por_klass = Feature.joins(:class_levels)
                       .select('features.id, features.name, class_levels.klass_id, class_levels.level')
                       .group_by { |f| f[:klass_id] }
    por_sub = Feature.joins(:sub_klass_levels)
                     .select('features.id, features.name, sub_klass_levels.sub_klass_id, sub_klass_levels.level')
                     .group_by { |f| f[:sub_klass_id] }

    Klass.order(:name).map do |k|
      da_classe = Array(por_klass[k.id])
      filhos = []
      if da_classe.any?
        filhos << { key: "k#{k.id}", name: "#{k.name} — features da classe",
                    features: lista_de_features(da_classe) }
      end
      SubKlass.where(klass_id: k.id).order(:name).each do |sk|
        fs = Array(por_sub[sk.id])
        next if fs.empty?

        filhos << { key: "sk#{sk.id}", name: sk.name, features: lista_de_features(fs) }
      end
      { key: k.id, name: k.name, children: filhos }
    end + [grupo_sem_classe].compact
  end

  # ⚠️ 389 das 1301 features não estão em `class_levels` NEM em
  # `sub_klass_levels` — "Frenesi", "Fúria Irracional", "Presença Intimidante".
  # Existem na tabela e são atreláveis, mas não há por onde as pendurar numa
  # classe.
  #
  # Medido: algumas vivem no `SubKlass#levels_json` (outro catálogo, que
  # coexiste e duplica — "Aura de Devoção" está nos dois) e outras em lado
  # nenhum. Recuperá-las por casamento de NOME contra esse JSON agruparia
  # errado, e agrupar errado é pior do que não agrupar: o mestre atrelaria a
  # magia à subclasse errada sem ver.
  #
  # Então ficam num grupo próprio, alcançáveis e honestamente rotuladas.
  def grupo_sem_classe
    ligadas = Feature.joins(:class_levels).distinct.pluck(:id) +
              Feature.joins(:sub_klass_levels).distinct.pluck(:id)
    soltas = Feature.where.not(id: ligadas.uniq).order(:name)
    return nil if soltas.empty?

    {
      key: 'sem-classe',
      name: '— sem classe associada —',
      children: [{ key: 'orfas', name: "#{soltas.size} features sem nível de classe",
                   features: soltas.map { |f| { key: f.id, name: f.name, level: nil } } }]
    }
  end

  def lista_de_features(linhas)
    linhas.map { |f| { key: f.id, name: f.name, level: f[:level] } }
          .uniq { |h| h[:key] }
          .sort_by { |h| [h[:level].to_i, h[:name].to_s] }
  end

  # A fonte tem de existir de verdade — `source_id` é um id sem FK, e uma
  # atrelagem para um id inexistente some da UI sem dizer porquê.
  def fonte_existe?(attrs)
    tipo = attrs[:source_type].to_s
    return false unless SpellSource::SOURCE_TYPES.include?(tipo)

    tipo.constantize.exists?(id: attrs[:source_id])
  rescue NameError
    false
  end

  def atrelagens_json(spell)
    SpellSource.where(spell_id: spell.id).order(:source_type, :id).map { |s| atrelagem_json(s) }
  end

  def atrelagem_json(src)
    alvo = src.source_record
    {
      id: src.id, source_type: src.source_type, source_id: src.source_id,
      source_name: alvo&.name, origin: src.origin,
      casting_mode: src.casting_mode, cost_label: src.cost_label,
      grant_mode: src.grant_mode, choose_count: src.choose_count,
      min_character_level: src.min_character_level, min_class_level: src.min_class_level,
      always_prepared: src.always_prepared, ability_override: src.ability_override,
      uses_per_long_rest: src.uses_per_long_rest, uses_per_short_rest: src.uses_per_short_rest,
      resource_key: src.resource_key, resource_cost: src.resource_cost,
      notes: src.notes
    }
  end

  def admin_spell_json(spell)
    idx = Spell.klass_api_indexes_by_spell_id([spell.id])[spell.id] || []
    spell.as_json(except: [:created_at, :updated_at]).merge('klass_api_indexes' => idx)
  end

  def derive_api_index(spell)
    base = spell.name.to_s
              .unicode_normalize(:nfd)
              .gsub(/\p{Mn}/, '')
              .downcase
              .gsub(/[^a-z0-9]+/, '-')
              .gsub(/^-|-$/, '')
    return nil if base.empty?
    base = "pt-#{base}"
    return base unless Spell.exists?(api_index: base)
    i = 2
    loop do
      candidate = "#{base}-#{i}"
      return candidate unless Spell.exists?(api_index: candidate)
      i += 1
    end
  end
end