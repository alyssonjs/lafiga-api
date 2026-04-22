class Api::V1::Public::MonstersController < ApplicationController
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
    monster = Monster.find_by(slug: params[:id]) || Monster.find(params[:id])
    render json: { monster: monster.to_payload }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
