class Api::V1::Public::GroupsController < ApplicationController
  before_action :set_group, only: [:show]

  def index
    @groups = Group.all
    render json: @groups
  end

  def show
    render json: @group
  end

  private

  def set_group
    @group = Group.find(params[:id])
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  end
end
