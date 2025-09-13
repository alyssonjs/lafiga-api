class Api::V1::Admin::DateDimensionsController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_date_dimension, only: [:show, :update, :destroy]

  def index
    year  = params.require(:year).to_i
    month = params.require(:month).to_i

    prev_month_date = Date.new(year, month, 1).prev_month
    next_month_date = Date.new(year, month, 1).next_month

    start_date = prev_month_date.beginning_of_month
    end_date   = next_month_date.end_of_month

    dates = DateDimension
              .where(date: start_date..end_date)
              .includes(
                schedule: [ :group, { schedule_characters: :character } ],
                schedules: [ :group, { schedule_characters: :character } ]
              )
              .order(:date)

    render json: dates, include: {
      schedule: {
        include: {
          group: { include: :characters },
          schedule_characters: { include: :character }
        },
        except: [:created_at, :updated_at]
      },
      schedules: {
        include: {
          group: { include: :characters },
          schedule_characters: { include: :character }
        },
        except: [:created_at, :updated_at]
      }
    }, status: :ok
  end

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
