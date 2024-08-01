class Api::V1::Player::GroupsController < ApplicationController
  before_action :authorize_request
  before_action :set_group, only: [:show, :update, :destroy]

  def index
    groups = Group.all
    render json: {groups: groups}, status: 200 
  end

  def show
    render json: {groups: @groups}, status: 200 
  end

  def create
    @group = Group.new(group_params)
    
    if @group.save
      render json: @group, status: :created
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @group.update(group_params)
      render json: {groups: @groups}, status: 200 
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @group.destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_group
    @group = Group.find(params[:id])
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end

  def group_params
    params.require(:group).permit(:name, :season, :day, :year, :description)
  end
end
