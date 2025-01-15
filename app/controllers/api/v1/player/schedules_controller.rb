class Api::V1::Player::SchedulesController < ApplicationController
  before_action :authorize_request
  before_action :set_schedule, only: [:show, :update, :destroy]

  def index
    schedules = @current_user.schedules
    render json: {schedules: schedules}, status: 200 
  end

  def show
    render json: {schedules: @schedule}, status: 200 
  end

  def create
    @group = @current_user.groups.find(schedule_params[:group_id])

    @schedule = Schedule.new(schedule_params)
    
    if @schedule.save
      render json: @schedule, status: :created
    else
      render json: { errors: @schedule.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @schedule.update(schedule_params)
      render json: {schedules: @schedule}, status: 200 
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
