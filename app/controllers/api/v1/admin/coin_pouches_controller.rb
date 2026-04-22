class Api::V1::Admin::CoinPouchesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # POST /api/v1/admin/sheets/:sheet_id/coin_pouches
  # body: { coin_pouch: { name: "Cofre do navio" } }
  def create
    name = params.dig(:coin_pouch, :name) || params[:name]
    @sheet.add_coin_pouch!(name.to_s)
    render json: { coin_pouches: @sheet.coin_pouches_for_api, wallet: @sheet.wallet_hash }, status: :created
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PATCH /api/v1/admin/sheets/:sheet_id/coin_pouches/:id
  # body: { coin_pouch: { name: "..." } }
  def update
    name = params.dig(:coin_pouch, :name) || params[:name]
    @sheet.rename_coin_pouch!(params[:id], name.to_s)
    render json: { coin_pouches: @sheet.coin_pouches_for_api, wallet: @sheet.wallet_hash }, status: :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /api/v1/admin/sheets/:sheet_id/coin_pouches/:id
  def destroy
    @sheet.destroy_coin_pouch!(params[:id])
    render json: { coin_pouches: @sheet.coin_pouches_for_api, wallet: @sheet.wallet_hash }, status: :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_sheet
    @sheet = Sheet.find(params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
