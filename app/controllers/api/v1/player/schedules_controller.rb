class Api::V1::Player::SchedulesController < ApplicationController
  before_action :authorize_request
  before_action :set_schedule, only: [:show, :update, :destroy]

  def index
    schedules = @current_user
                  .schedules
                  .joins(:date_dimension)
                  .order('date_dimensions.date ASC')
    render json: {schedules: schedules}, include: [:group, :date_dimension], status: 200 
  end

  def show
    render json: { schedule: @schedule }, include: [:group, :date_dimension], status: 200
  end

  def create
    # Security: ensure the chosen group belongs to current user
    gid = schedule_params[:group_id]
    unless @current_user.groups.exists?(id: gid)
      return render json: { error: 'Grupo inválido para este usuário' }, status: :forbidden
    end

    # Players always create schedules as 'waiting'
    attrs = schedule_params.merge(status: :waiting)

    schedule_service = ScheduleService.new(attrs)
    @schedule = schedule_service.call
    render json: { schedule: @schedule.result }, include: [:group, :date_dimension], status: :created
  end

  def update
    if @schedule.update(schedule_params)
      render json: { schedule: @schedule }, include: [:group, :date_dimension], status: 200 
    else
      render json: { errors: @schedule.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @schedule.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_schedule
    @schedule = @current_user.schedules.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def schedule_params
    params.require(:schedule).permit(:status, :date_dimension_id, :group_id, :title)
  end
end
