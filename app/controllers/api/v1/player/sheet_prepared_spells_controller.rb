class Api::V1::Player::SheetPreparedSpellsController < ApplicationController
  before_action :authorize_request

  def index
    sheet = current_user_sheet
    prepared = SheetPreparedSpell.where(sheet_id: sheet.id)
    render json: { sheet_prepared_spells: prepared }, status: :ok
  end

  def create
    sheet = current_user_sheet
    # Gate against limit using best-effort prepared classes
    begin
      prep_klass = sheet.sheet_klasses.includes(:klass).map(&:klass).find { |k| %w[cleric druid wizard paladin].include?(k.api_index) }
      if prep_klass
        limit = SpellRules.prepared_limit_for(sheet, prep_klass)
        non_auto = SheetPreparedSpell.where(sheet_id: sheet.id, auto: false).count
        if non_auto >= limit
          return render json: { error: "Limite de magias preparadas alcançado (#{non_auto}/#{limit})" }, status: :unprocessable_entity
        end
      end
    rescue => _e
      # if any error, skip gate and let model validations handle (none by default)
    end

    sp = SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: params[:spell_id], auto: ActiveModel::Type::Boolean.new.cast(params[:auto]), source: 'class')
    render json: { sheet_prepared_spell: sp }, status: :created
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    sheet = current_user_sheet
    sp = SheetPreparedSpell.find_by!(sheet_id: sheet.id, id: params[:id])
    sp.destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  private

  def current_user_sheet
    sheet = Sheet.find(params[:sheet_id])
    raise StandardError, 'Forbidden' unless sheet.character.user_id == @current_user.id
    sheet
  end
end
