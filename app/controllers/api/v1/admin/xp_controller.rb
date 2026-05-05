class Api::V1::Admin::XpController < ApplicationController
  # DM site-wide e' o unico papel que pode mexer em XP (concessao da
  # mesa). Players apenas leem via summary. Roteamento espelha o de
  # `wallets_controller` para manter consistencia (PUT/GET sob sheet).
  before_action :authorize_site_wide_dm
  before_action :set_sheet

  # GET /api/v1/admin/sheets/:sheet_id/xp
  def show
    render json: xp_payload, status: :ok
  end

  # PUT /api/v1/admin/sheets/:sheet_id/xp
  # body:
  #   { delta: <int> }                       — soma/subtrai XP
  #   { xp: <int> }                          — define XP absoluto
  #   { milestone: true }                    — XP do proximo nivel (DM milestone)
  def update
    if params.key?(:milestone) && truthy?(params[:milestone])
      @sheet.advance_xp_to_next_level!
    elsif params.key?(:delta)
      @sheet.apply_xp_delta!(params[:delta])
    elsif params.key?(:xp)
      @sheet.set_xp!(params[:xp])
    else
      return render(json: { errors: 'Informe `delta`, `xp` ou `milestone`' }, status: :unprocessable_entity)
    end

    render json: xp_payload, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound => e
    render json: { errors: e.message }, status: :not_found
  rescue => e
    render json: { errors: e.message }, status: :unprocessable_entity
  end

  private

  def xp_payload
    cur = @sheet.current_level.to_i.clamp(1, Sheet::MAX_LEVEL)
    next_threshold = cur >= Sheet::MAX_LEVEL ? nil : Sheet::XP_THRESHOLDS[cur + 1].to_i
    {
      sheet_id: @sheet.id,
      experience_points: @sheet.experience_points.to_i,
      current_level: cur,
      next_level_threshold: next_threshold,
      max_level: Sheet::MAX_LEVEL
    }
  end

  def truthy?(v)
    case v
    when true, 'true', '1', 1 then true
    else false
    end
  end

  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end
end
