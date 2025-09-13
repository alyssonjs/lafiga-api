class Api::V1::Player::ScheduleCharactersController < ApplicationController
  before_action :authorize_request
  before_action :set_schedule_character, only: [:show, :update]

  # Optional list for user; can filter by schedule_id
  def index
    rel = ScheduleCharacter.joins(:character)
                           .where(characters: { user_id: @current_user.id })
    rel = rel.where(schedule_id: params[:schedule_id]) if params[:schedule_id]
    render json: { schedule_characters: rel.as_json(include: [:schedule, :character]) }, status: :ok
  end

  def show
    render json: { schedule_character: @schedule_character.as_json(include: [:schedule, :character]) }, status: :ok
  end

  def update
    unless %w[confirmed pending].include?(schedule_character_params[:status].to_s)
      return render json: { error: 'Status inválido' }, status: :unprocessable_entity
    end

    if @schedule_character.update(schedule_character_params)
      render json: { schedule_character: @schedule_character }, status: :ok
    else
      render json: { errors: @schedule_character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_schedule_character
    @schedule_character = ScheduleCharacter
                            .joins(:character)
                            .where(characters: { user_id: @current_user.id })
                            .find(params[:id])
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  def schedule_character_params
    params.require(:schedule_character).permit(:status)
  end
end

