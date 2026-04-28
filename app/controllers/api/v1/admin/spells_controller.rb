class Api::V1::Admin::SpellsController < ApplicationController
  # Compendio / editor de magias: mesmos mestres que itens magicos (DM site-wide + Admin).
  # `authorize_admin_request` barrava DM e o front recebia 401 (apiClient limpava sessao).
  before_action :authorize_site_wide_dm
  before_action :set_spell, only: [:show, :update, :destroy]

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
    render json: { spell: @spell.as_json(except: [:created_at, :updated_at]).merge('klass_api_indexes' => idx) }, status: :ok
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
  # Remove todas as SpellSource (classes/subclasses, etc.) — sao apenas ligacoes
  # de catalogo; "Remover" no grimorio do DM deve apagar a magia de facto.
  #
  # Continua bloqueando se a magia ainda existir em fichas (known/prepared),
  # onde apagar seria destrutivo para personagens.
  def destroy
    known_n = SheetKnownSpell.where(spell_id: @spell.id).count
    prep_n = SheetPreparedSpell.where(spell_id: @spell.id).count
    if known_n.positive? || prep_n.positive?
      render json: {
        error: 'spell_on_sheets',
        message: 'Magia ainda esta em uma ou mais fichas (conhecidas ou preparadas). Remova ou substitua nas fichas antes de apagar.',
        sheet_known_spells: known_n,
        sheet_prepared_spells: prep_n
      }, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
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

  def permitted
    params.require(:spell).permit(
      :api_index, :name, :level, :school, :range,
      :components, :material, :ritual, :duration,
      :concentration, :casting_time, :desc, :higher_level
    )
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