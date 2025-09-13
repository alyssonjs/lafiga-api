class Api::V1::Public::SchedulesController < ApplicationController
  before_action :set_schedule, only: [:show]

  def index
    @schedules = Schedule
      .joins(:date_dimension)
      .where(date_dimensions: { date: Date.current.. })
      .order('date_dimensions.date ASC')

    render json: { schedules: @schedules.as_json(include: [:group, :date_dimension]) }
  end

  def show
    render json: { schedule: @schedule }, include: [:group, :date_dimension]
  end

  private

  def set_schedule
    @schedule = Schedule.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
