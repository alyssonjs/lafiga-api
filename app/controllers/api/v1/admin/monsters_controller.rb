class Api::V1::Admin::MonstersController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_monster, only: [:show, :update, :destroy]

  def index
    scope = Monster.all
    scope = scope.by_type(params[:type] || params[:monster_type])
    scope = scope.by_source(params[:source])
    scope = scope.by_cr_min(params[:cr_min])
    scope = scope.by_cr_max(params[:cr_max])
    scope = scope.search(params[:q] || params[:search])
    scope = scope.order(:cr_numeric, :name).limit(500)
    render json: { monsters: scope.map(&:to_payload) }, status: :ok
  end

  def show
    render json: { monster: @monster.to_payload }, status: :ok
  end

  def create
    @monster = Monster.new(permitted_attrs)
    if @monster.save
      render json: { monster: @monster.to_payload }, status: :created
    else
      render json: { errors: @monster.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @monster.update(permitted_attrs)
      render json: { monster: @monster.to_payload }, status: :ok
    else
      render json: { errors: @monster.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @monster.destroy
    head :no_content
  end

  # POST /api/v1/admin/monsters/bulk_import
  #
  # Aceita:
  #   • `yaml`:    string YAML
  #   • `monsters`: Hash { slug => attrs } OU Array [{id, name, ...}]
  #   • `dry_run`: "true" para apenas validar
  def bulk_import
    payload =
      if params[:yaml].present?
        params[:yaml].to_s
      elsif params[:monsters].present?
        params[:monsters].respond_to?(:to_unsafe_h) ? params[:monsters].to_unsafe_h : params[:monsters]
      else
        return render json: { error: 'Provide "yaml" (string) or "monsters" (object/array).' },
                      status: :unprocessable_entity
      end

    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    result  = MonsterEngineSyncService.call(payload, dry_run: dry_run)

    render json: {
      dry_run:  dry_run,
      upserted: result.upserted,
      created:  result.created,
      updated:  result.updated,
      skipped:  result.skipped,
      errors:   result.errors,
      details:  result.details,
    }, status: :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Psych::SyntaxError => e
    render json: { error: "YAML invalido: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def set_monster
    @monster = Monster.find_by(slug: params[:id]) || Monster.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  # Aceita tanto o shape "rico" (todo MonsterEntry no `payload`) quanto
  # campos top-level (name, source, cr, etc) sendo movidos para o JSONB.
  # Isso permite ao MagicItemEditor-style admin enviar { monster: { ... } }
  # com o mesmo shape do front.
  def permitted_attrs
    raw = params.require(:monster).to_unsafe_h
    payload =
      if raw['payload'].is_a?(Hash)
        raw['payload']
      else
        raw.except('name', 'slug', 'source', 'name_en')
      end
    {
      name:    raw['name'],
      slug:    raw['slug'].presence,
      name_en: raw['name_en'].presence || raw.dig('payload', 'nameEN'),
      source:  raw['source'].presence || 'homebrew',
      payload: payload || {},
    }.compact
  end
end
