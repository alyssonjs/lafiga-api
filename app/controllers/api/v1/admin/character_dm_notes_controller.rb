# frozen_string_literal: true

# Notas privadas do mestre por personagem (nao expostas ao jogador).
# GET/PUT /api/v1/admin/characters/:character_id/dm_notes
class Api::V1::Admin::CharacterDmNotesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_character

  def show
    render json: { dm_notes: @character.dm_notes.to_s }, status: :ok
  end

  def update
    @character.update!(dm_notes: dm_notes_body)
    render json: { dm_notes: @character.dm_notes.to_s }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_character
    @character = Character.find(params[:character_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Character not found' }, status: :not_found
  end

  def dm_notes_body
    return params[:dm_notes].to_s if params.key?(:dm_notes)

    ch = params[:character]
    return '' unless ch.is_a?(ActionController::Parameters)

    ch.permit(:dm_notes)[:dm_notes].to_s
  end
end
