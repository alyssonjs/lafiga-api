class Api::V1::Admin::GroupsController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_group, only: [:show, :update, :destroy]

  def index
    groups = Group.all
    render json: {groups: groups}, status: 200 
  end

  def show
    render json: {groups: @group}, status: 200 
  end

  def create
    @group = Group.new(group_params)
    
    if @group.save
      render json: @group, status: :created
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @group.update(group_params)
      render json: {groups: @group}, status: 200 
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @group.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_group
    @group = Group.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def group_params
    params.require(:group).permit(:name, :season, :day, :year, :description)
  end
end
