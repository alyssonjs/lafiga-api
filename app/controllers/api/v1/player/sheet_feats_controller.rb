class Api::V1::Player::SheetFeatsController < ApplicationController
  before_action :authorize_request

  def destroy
    sheet_feat = SheetFeat.find(params[:id])
    sheet = sheet_feat.sheet

    # Ownership check: the sheet must belong to the current user
    unless sheet.character.user_id == @current_user.id
      render json: { error: 'Forbidden' }, status: :forbidden and return
    end

    sheet_feat.destroy
    render json: { message: 'Deleted successfully' }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not Found' }, status: :not_found
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end


