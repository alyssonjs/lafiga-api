class Api::V1::Public::MagicItemsController < ApplicationController
  def index
    scope = MagicItem.all
    scope = scope.by_rarity(params[:rarity])
    scope = scope.by_category(params[:category])
    scope = scope.attuned(params[:attuned]) if params.key?(:attuned)
    scope = scope.search(params[:q] || params[:search])
    scope = scope.order(:name)
    render json: { magic_items: scope.limit(500).as_json(except: [:created_at, :updated_at]) }
  end

  def show
    item = MagicItem.find_by(slug: params[:id]) || MagicItem.find(params[:id])
    render json: { magic_item: item.as_json(except: [:created_at, :updated_at]) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end

