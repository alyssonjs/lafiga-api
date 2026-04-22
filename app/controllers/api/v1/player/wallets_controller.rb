class Api::V1::Player::WalletsController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet

  # GET /api/v1/player/sheets/:sheet_id/wallet
  def show
    render json: {
      wallet: @sheet.wallet_hash,
      coin_pouches: @sheet.coin_pouches_for_api
    }, status: :ok
  end

  # PUT /api/v1/player/sheets/:sheet_id/wallet
  # body:
  #   { wallet: { cp:, sp:, ... } }                    → substitui **uma** algibeira
  #   { wallet: {...}, pouch_id: "uuid" }             → substitui essa algibeira
  #   { delta:  {...}, pouch_id: "uuid" } (opcional)   → delta na algibeira (default: primary)
  def update
    pouch_id = params[:pouch_id].presence

    if params[:delta].present?
      delta = params[:delta].is_a?(ActionController::Parameters) ? params[:delta].to_unsafe_h : params[:delta]
      if pouch_id
        @sheet.apply_coin_delta_to_pouch!(pouch_id, delta)
      else
        @sheet.apply_coin_delta!(delta)
      end
    elsif params[:wallet].present?
      values = params[:wallet].is_a?(ActionController::Parameters) ? params[:wallet].to_unsafe_h : params[:wallet]
      if pouch_id
        @sheet.set_pouch_wallet!(pouch_id, values)
      else
        @sheet.set_wallet!(values)
      end
    else
      return render(json: { error: "Informe `wallet` ou `delta`" }, status: :unprocessable_entity)
    end

    render json: { wallet: @sheet.wallet_hash, coin_pouches: @sheet.coin_pouches_for_api }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_sheet
    @sheet = @current_user.sheets.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
