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
  #   { coin_transfer: { from_pouch_id:, to_pouch_id:, wallet: { cp:, ... } } } → debita origem, credita destino
  def update
    pouch_id = params[:pouch_id].presence

    if params[:coin_transfer].present?
      ct = coin_transfer_params
      @sheet.transfer_pouch_coins!(ct[:from_pouch_id], ct[:to_pouch_id], ct[:wallet] || {})
    elsif params[:delta].present?
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
      return render(json: { error: "Informe `wallet`, `delta` ou `coin_transfer`" }, status: :unprocessable_entity)
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

  def coin_transfer_params
    p = params.require(:coin_transfer).permit(:from_pouch_id, :to_pouch_id, wallet: Sheet::COIN_KEYS)
    {
      from_pouch_id: p[:from_pouch_id].to_s,
      to_pouch_id: p[:to_pouch_id].to_s,
      wallet: (p[:wallet].presence || {}).to_h
    }
  end

  def set_sheet
    # Paridade com Api::V1::Player::SheetsController#sheets_scope_for_current_user
    # — o Mestre (fluxo /character/:id?dm=true) precisa de ler/ajustar algibeira
    # de personagens de outros utilizadores.
    sheet_id = params[:id].presence || params[:sheet_id].presence
    scope = Group.user_is_dm?(@current_user) ? Sheet : @current_user.sheets
    @sheet = scope.find(sheet_id)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
