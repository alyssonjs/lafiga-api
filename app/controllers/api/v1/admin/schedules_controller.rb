class Api::V1::Admin::SchedulesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_schedule, only: [:show, :update, :destroy]

  # Lista paginada com filtros — usado pelo painel administrativo. Aceita:
  #   ?group_id= ?status= ?from=YYYY-MM-DD ?to= ?page= ?per_page=
  def index
    base = Schedule.includes(:date_dimension, :group, :schedule_characters)

    base = base.where(group_id: params[:group_id]) if params[:group_id].present?
    if params[:status].present?
      statuses = Array(params[:status]).map(&:to_s).flat_map { |s| s.split(',') } & Schedule.statuses.keys
      base = base.where(status: statuses) if statuses.any?
    end
    if params[:from].present? || params[:to].present?
      base = base.joins(:date_dimension)
      base = base.where('date_dimensions.date >= ?', Date.parse(params[:from])) if params[:from].present?
      base = base.where('date_dimensions.date <= ?', Date.parse(params[:to])) if params[:to].present?
    end

    page     = [params[:page].to_i, 1].max
    per_page = (params[:per_page].to_i.between?(1, 200) ? params[:per_page].to_i : 50)
    offset   = (page - 1) * per_page

    total = base.count
    records = base.joins(:date_dimension)
                  .order('date_dimensions.date ASC')
                  .limit(per_page)
                  .offset(offset)

    render json: {
      schedules: ScheduleSerializer.serialize_collection(records, viewer: @current_user),
      meta: { page: page, per_page: per_page, total: total },
    }, status: 200
  end

  def show
    render json: { schedule: ScheduleSerializer.serialize(@schedule) }, status: 200
  end

  def create
    result = ScheduleService.new(schedule_params, current_user: @current_user).call
    if result.success?
      render json: { schedule: ScheduleSerializer.serialize(result.result) }, status: :created
    else
      render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    if @schedule.update(schedule_params)
      render json: { schedule: ScheduleSerializer.serialize(@schedule) }, status: 200
    else
      render json: { errors: @schedule.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @schedule.destroy
    render json: { message: "Deletado com sucesso" }, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_schedule
    @schedule = Schedule.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def schedule_params
    params.require(:schedule).permit(
      :status, :date_dimension_id, :date, :group_id, :title,
      :description, :dm_notes, :summary, :xp_awarded,
      :scheduled_time, :campaign_name,
      :started_at, :ended_at, :battle_map_id,
      highlights: [:text, :type]
    )
  end
end
