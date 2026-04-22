# Endpoints de runtime state da ficha (estado mutável que muda durante o
# jogo). Veja `SheetRuntimeState` para a justificativa de não usar
# `sheets.metadata`.
#
# Rotas (definidas como member em /api/v1/player/sheets/:id):
#   GET    /api/v1/player/sheets/:id/runtime
#   PATCH  /api/v1/player/sheets/:id/runtime
#   POST   /api/v1/player/sheets/:id/runtime/short_rest
#   POST   /api/v1/player/sheets/:id/runtime/long_rest
class Api::V1::Player::SheetRuntimeStatesController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet

  def show
    runtime = @sheet.runtime!
    render json: { runtime_state: runtime.as_payload }, status: :ok
  end

  def update
    runtime = @sheet.runtime!
    runtime.apply_patch!(patch_params)
    render json: { runtime_state: runtime.as_payload }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[SheetRuntime#update] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def short_rest
    runtime = Sheets::Runtime::ApplyShortRestService.call(@sheet)
    render json: { runtime_state: runtime.as_payload }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def long_rest
    runtime = Sheets::Runtime::ApplyLongRestService.call(@sheet)
    render json: { runtime_state: runtime.as_payload }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_sheet
    # Mesmo critério que `Api::V1::Player::SheetsController#set_sheet`: mestre
    # (DM/Admin site-wide via `Group.user_is_dm?`) pode mutar runtime de
    # qualquer ficha — fluxo da ficha com `?dm=true` e sessão de jogo.
    @sheet = sheets_scope_for_current_user.find(params[:sheet_id] || params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def sheets_scope_for_current_user
    return Sheet.all if Group.user_is_dm?(@current_user)

    @current_user.sheets
  end

  # Strong params permitem todas as fatias (A/B/C). O service atual aplica
  # apenas o que foi enviado (apply_patch! checa `key?`).
  #
  # Aceita tanto envelope `{ runtime_state: { ... } }` quanto chaves no topo,
  # para tolerar clientes diversos. Usa `to_unsafe_h` ao final para deserializar
  # totalmente os hashes JSONB aninhados (death_saves, hit_dice_used etc.) — o
  # filtro de chaves de topo já protege contra extras.
  def patch_params
    base = params[:runtime_state].is_a?(ActionController::Parameters) ? params[:runtime_state] : params
    base.permit(
      :exhaustion,
      death_saves: {},
      hit_dice_used: {},
      conditions: [],
      concentration: {},
      spell_slots_used: {},
      class_resources_used: {}
    ).to_unsafe_h
  end
end
