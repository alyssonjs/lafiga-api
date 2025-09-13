class Api::V1::Admin::MagicItemsController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_item, only: [:show, :update, :destroy]

  def index
    scope = MagicItem.all.order(:name)
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

  private

  def set_item
    @item = MagicItem.find_by(slug: params[:id]) || MagicItem.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def permitted
    params.require(:magic_item).permit(
      :name, :slug, :rarity, :category, :sub_category,
      :requires_attunement, :attunement_note,
      :weight_kg, :value_gp, :source,
      :cursed, :curse_text, :charges, :recharge,
      :description,
      { bonuses: {} }, { properties: {} }, { tags: [] }, { effects: [] }
    )
  end
end
