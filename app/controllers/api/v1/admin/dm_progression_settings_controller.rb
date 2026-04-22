# frozen_string_literal: true

class Api::V1::Admin::DmProgressionSettingsController < ApplicationController
  before_action :authorize_site_wide_dm

  # GET /api/v1/admin/dm_progression_settings
  def show
    render json: { progression_settings: DmProgressionSettingsMerge.read_merged(@current_user) }, status: :ok
  end

  # PATCH /api/v1/admin/dm_progression_settings
  # Body: { progression_settings: { xp_thresholds: { "2" => 300, "3" => 900 } } }
  def update
    ps = params[:progression_settings].presence || params[:dm_progression_settings]
    unless ps.is_a?(ActionController::Parameters) || ps.is_a?(Hash)
      return render json: { errors: ['progression_settings required'] }, status: :unprocessable_entity
    end

    h = ps.is_a?(ActionController::Parameters) ? ps.to_unsafe_h : ps.deep_stringify_keys
    xp_in = h['xp_thresholds']
    unless xp_in.nil? || xp_in.is_a?(Hash)
      return render json: { errors: ['xp_thresholds must be a hash'] }, status: :unprocessable_entity
    end

    current = (@current_user.progression_settings || {}).deep_stringify_keys
    existing_xp = (current['xp_thresholds'].is_a?(Hash) ? current['xp_thresholds'] : {}).stringify_keys
    incoming = (xp_in || {}).deep_stringify_keys
    merged_xp = existing_xp.merge(incoming)
    next_settings = current.merge('xp_thresholds' => merged_xp)
    @current_user.update!(progression_settings: next_settings)

    render json: { progression_settings: DmProgressionSettingsMerge.read_merged(@current_user) }, status: :ok
  end
end
