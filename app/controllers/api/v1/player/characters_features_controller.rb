class Api::V1::Player::CharactersFeaturesController < ApplicationController
  before_action :authorize_request

  def index
    character = @current_user.characters.find(params.require(:character_id))

    # Ensure all current class/subclass features are granted (idempotent)
    unless params[:sync] == 'false'
      sheet = Sheet.find_by(character_id: character.id)
      if sheet
        sheet.sheet_klasses.includes(:klass).each do |sk|
          FeatureGrantService.call(sheet: sheet, klass: sk.klass, from_level: 0, to_level: sk.level)
        end
      end
    end

    records = CharactersFeature.includes(:feature).where(character_id: character.id)
    render json: {
      characters_features: records.as_json(only: [:id, :character_id, :feature_id, :show, :gained_at_level, :source_type, :source_id], include: { feature: { only: [:id, :name, :description] } })
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    cf = CharactersFeature.find(params[:id])
    raise StandardError, 'Forbidden' unless cf.character.user_id == @current_user.id
    if cf.update(update_params)
      render json: { characters_feature: cf }, status: :ok
    else
      render json: { errors: cf.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def update_params
    params.require(:characters_feature).permit(:show)
  end
end
