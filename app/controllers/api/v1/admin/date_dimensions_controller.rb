class Api::V1::Admin::DateDimensionsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_date_dimension, only: [:update]

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
      render json: { date_dimension: @date_dimension }, status: 200
    else
      render json: { errors: @date_dimension.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/date_dimensions/set_availability_by_date
  # Body: { date: "2026-04-20", available: false } — cria DateDimension se preciso
  # (mesmo helper do ScheduleService) para permitir veto antes de existir sessão.
  def set_availability_by_date
    date_s = params.require(:date)
    available = ActiveModel::Type::Boolean.new.cast(params.require(:available))
    d = Date.parse(date_s.to_s)
    id = ScheduleService.ensure_date_dimension(d.iso8601)
    dd = DateDimension.find(id)
    dd.update!(available: available)
    render json: { date_dimension: dd.as_json }, status: 200
  rescue ArgumentError => e
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
