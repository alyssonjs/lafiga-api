class Api::V1::Player::SheetKnownSpellsController < ApplicationController
  before_action :authorize_request

  def index
    sk = current_user_sheet_klass
    known = SheetKnownSpell.where(sheet_klass_id: sk.id)
    render json: { sheet_known_spells: known }, status: :ok
  end

  def create
    sk = current_user_sheet_klass
    service = SpellLearningService.call(sheet_klass: sk, spell_id: params[:spell_id])
    if service.success?
      ks = SheetKnownSpell.find_by!(sheet_klass_id: sk.id, spell_id: params[:spell_id])
      render json: { sheet_known_spell: ks }, status: :created
    else
      render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    sk = current_user_sheet_klass
    ks = SheetKnownSpell.find_by!(sheet_klass_id: sk.id, id: params[:id])
    ks.destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  private

  def current_user_sheet_klass
    sk = SheetKlass.find(params[:sheet_klass_id])
    raise StandardError, 'Forbidden' unless sk.sheet.character.user_id == @current_user.id
    sk
  end
end
