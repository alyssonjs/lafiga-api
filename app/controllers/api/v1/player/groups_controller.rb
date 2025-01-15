class Api::V1::Player::GroupsController < ApplicationController
  before_action :authorize_request
  before_action :get_groups, only: [:show]

  def index
    groups = @current_user.groups
    render json: {groups: groups}, status: 200 
  end

  def show
    render json: {group: @group}, status: 200
  end

  private

  def get_groups
    @group =  @current_user.groups.find(params[:id])
  rescue StandardError => e 
    render json: { errors: e.message }, status: :not_found
  end
end