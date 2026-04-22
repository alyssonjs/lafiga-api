# frozen_string_literal: true

class Api::V1::Admin::CharacterDmLevelUnlocksController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_character

  # POST /api/v1/admin/characters/:character_id/dm_level_unlock
  def create
    rec = CharacterDmLevelUnlock.find_or_initialize_by(character_id: @character.id)
    rec.unlocked_by_user = @current_user
    unless rec.save
      return render json: { errors: rec.errors.full_messages }, status: :unprocessable_entity
    end

    head :no_content
  end

  # DELETE /api/v1/admin/characters/:character_id/dm_level_unlock
  def destroy
    CharacterDmLevelUnlock.where(character_id: @character.id).destroy_all
    head :no_content
  end

  private

  def set_character
    @character = Character.find(params[:character_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'not_found' }, status: :not_found
  end
end
