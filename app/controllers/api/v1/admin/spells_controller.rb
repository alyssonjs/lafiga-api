class Api::V1::Admin::SpellsController < ApplicationController
  before_action :authorize_admin_request
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
    render json: { spells: scope.as_json(except: [:created_at, :updated_at]) }, status: :ok
  end

  def show
    render json: { spell: @spell.as_json(except: [:created_at, :updated_at]) }, status: :ok
  end

  def create
    attrs = permitted
    @spell = Spell.new(attrs)
    @spell.api_index = derive_api_index(@spell) if @spell.api_index.blank?
    if @spell.api_index.blank?
      render json: { errors: ['name e obrigatorio para gerar o api_index'] }, status: :unprocessable_entity
      return
    end
    if @spell.save
      render json: { spell: @spell }, status: :created
    else
      render json: { errors: @spell.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @spell.update(permitted)
      render json: { spell: @spell }, status: :ok
    else
      render json: { errors: @spell.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/spells/:id
  #
  # Bloqueia se houver SpellSource referenciando (classes/subclasses/etc).
  # Devolve 422 com a lista de fontes para o front exibir o motivo.
  def destroy
    sources = SpellSource.where(spell_id: @spell.id).to_a
    if sources.any?
      render json: {
        error: 'spell_in_use',
        message: 'Magia esta vinculada a outras entidades; remova as fontes antes de apagar.',
        sources: sources.map { |s| { source_type: s.source_type, source_id: s.source_id } }
      }, status: :unprocessable_entity
      return
    end
    @spell.destroy
    head :no_content
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
