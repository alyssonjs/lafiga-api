# frozen_string_literal: true

class Api::V1::Admin::BackgroundsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_background, only: %i[show update destroy]

  def index
    scope = Background.order(:name).limit(500)
    scope = scope.where('api_index ILIKE ? OR name ILIKE ?', "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
    render json: { backgrounds: scope.map { |b| serialize(b) } }, status: :ok
  end

  def show
    render json: { background: serialize(@background, full: true) }, status: :ok
  end

  def create
    @background = Background.new(build_attrs)
    if @background.save
      render json: { background: serialize(@background, full: true) }, status: :created
    else
      render json: { errors: @background.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    attrs = build_attrs
    if attrs[:rules].is_a?(Hash)
      attrs[:rules] = (@background.rules || {}).deep_merge(attrs[:rules])
    end
    if @background.update(attrs)
      render json: { background: serialize(@background, full: true) }, status: :ok
    else
      render json: { errors: @background.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if @background.sheets.exists?
      render json: {
        error: 'background_in_use',
        sheets: @background.sheets.pluck(:id)
      }, status: :unprocessable_entity
    else
      @background.destroy!
      head :no_content
    end
  end

  private

  def set_background
    @background = Background.find_by(api_index: params[:id]) || Background.find_by(id: params[:id])
    return if @background

    render json: { error: 'Not found' }, status: :not_found
  end

  def build_attrs
    p = params.require(:background).permit(
      :api_index, :name, :feature_name, :feature_desc, :parent_api_index, :published, :data_json
    )
    h = p.to_h
    if params[:background].key?(:rules)
      raw = params[:background][:rules]
      h[:rules] =
        if raw.is_a?(ActionController::Parameters)
          raw.permit!.to_h
        elsif raw.is_a?(Hash)
          raw.stringify_keys
        else
          {}
        end
    end
    h.compact
  end

  def serialize(bg, full: false)
    base = {
      id: bg.id,
      api_index: bg.api_index,
      name: bg.name,
      parent_api_index: bg.parent_api_index,
      published: bg.published,
      feature_name: bg.feature_name,
      feature_desc: bg.feature_desc,
      rules_summary: bg.rules.is_a?(Hash) ? bg.rules.keys.take(12) : []
    }
    return base unless full

    base.merge(
      rules: bg.rules || {},
      data_json: bg.data_json
    )
  end
end
