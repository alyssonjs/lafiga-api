class Api::V1::Admin::MagicItemsController < ApplicationController
  # Strong params: `effects: []` sozinho descarta hashes dentro do array (Rails
  # só aceita escalares no array). Listar chaves por elemento para o JSONB
  # persistir ao criar/editar pelo editor DM.
  MAGIC_ITEM_EFFECTS_PERMIT = [
    :kind,
    :value,
    :type,
    :note,
    :dice,
    :flat,
    :damage_type,
    :ability,
    :name,
    :desc,
    :source,
    # scroll_spell (pergaminho): magia real do catálogo + nível p/ CD/ataque (D3-A)
    :spell_name,
    :spell_api_index,
    :spell_level,
    { damage_types: [] },
    { conditions: [] },
    { abilities: [] },
    { skills: [] },
  ].freeze

  # Compêndio / editor de itens mágicos: mestres site-wide (DM) e Admin — não só papel "Admin"
  # (authorize_admin_request barrava DM e o front recebia 401 → logout global no apiClient).
  before_action :authorize_site_wide_dm
  before_action :set_item, only: [:show, :update, :destroy]

  def index
    scope = MagicItem.all
    scope = scope.by_rarity(params[:rarity])           if params[:rarity].present?
    scope = scope.by_category(params[:category])       if params[:category].present?
    scope = scope.attuned(params[:attuned])            if params.key?(:attuned)
    scope = scope.search(params[:q] || params[:search])
    scope = scope.order(:name).limit(500)
    render json: { magic_items: scope.as_json(except: [:created_at, :updated_at]) }, status: :ok
  end

  def show
    render json: { magic_item: @item.as_json(except: [:created_at, :updated_at]) }, status: :ok
  end

  def create
    @item = MagicItem.new(permitted)
    if @item.save
      render json: { magic_item: @item }, status: :created
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @item.update(permitted)
      render json: { magic_item: @item }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy
    head :no_content
  end

  # POST /api/v1/admin/magic_items/bulk_import
  #
  # Aceita YAML (string) ou Hash-parseada no formato padrão:
  #   { "magic_items" => { "<slug>" => { ...attrs... }, ... } }
  #
  # Params suportados:
  #   • `yaml`:    string YAML crua
  #   • `items`:   Hash já parseada (útil quando o front-end parseia localmente)
  #   • `dry_run`: se "true", apenas valida sem persistir
  def bulk_import
    payload =
      if params[:yaml].present?
        params[:yaml].to_s
      elsif params[:items].present?
        params[:items].respond_to?(:to_unsafe_h) ? params[:items].to_unsafe_h : params[:items]
      else
        return render json: { error: 'Provide "yaml" (string) or "items" (object).' }, status: :unprocessable_entity
      end

    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    result  = MagicItemEngineSyncService.call(payload, dry_run: dry_run)

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
    render json: { error: "YAML inválido: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def set_item
    @item = MagicItem.find_by(slug: params[:id]) || MagicItem.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def permitted
    params.require(:magic_item).permit(
      :name, :slug, :rarity, :category, :sub_category, :is_wondrous,
      :requires_attunement, :attunement_note,
      :weight_kg, :value_gp, :source,
      :cursed, :curse_text, :charges, :recharge,
      :description,
      { bonuses: {} }, { properties: {} }, { tags: [] }, { effects: MAGIC_ITEM_EFFECTS_PERMIT }
    )
  end
end
