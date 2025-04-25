class Api::V1::Admin::DateDimensionsController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_date_dimension, only: [:show, :update, :destroy]

  def update
    if @date_dimension.update!(date_dimension_params)
      render json: {date_dimension: @date_dimension}, status: 200
    else
      render json: { errors: @date_dimension.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_date_dimension
    @date_dimension = DateDimension.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def date_dimension_params
    params.require(:date_dimension).permit(:available)
  end
end
