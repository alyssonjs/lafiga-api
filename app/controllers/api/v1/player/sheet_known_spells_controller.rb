class Api::V1::Player::SheetKnownSpellsController < ApplicationController
  before_action :authorize_request

  def index
    sk = current_user_sheet_klass
    known = SheetKnownSpell.where(sheet_klass_id: sk.id)
    render json: { sheet_known_spells: known }, status: :ok
  end

  def create
    sk = current_user_sheet_klass
    spell_id = params[:spell_id] || params.dig(:sheet_known_spell, :spell_id)
    grimoire = ActiveModel::Type::Boolean.new.cast(
      params[:grimoire_expansion] || params.dig(:sheet_known_spell, :grimoire_expansion),
    )

    if grimoire
      unless sk.klass.api_index == 'wizard'
        return render json: { error: 'Apenas magos podem expandir o grimório desta forma.' }, status: :unprocessable_entity
      end
      spell = Spell.find(spell_id)
      if SheetKnownSpell.exists?(sheet_klass_id: sk.id, spell_id: spell.id)
        return render json: { error: 'Magia já está no grimório.' }, status: :unprocessable_entity
      end
      ks = SheetKnownSpell.create!(
        sheet_klass: sk,
        spell: spell,
        gained_at_class_level: sk.level,
        source: 'grimoire',
      )
      return render json: { sheet_known_spell: ks }, status: :created
    end

    service = SpellLearningService.call(sheet_klass: sk, spell_id: spell_id)
    if service.success?
      ks = SheetKnownSpell.find_by!(sheet_klass_id: sk.id, spell_id: spell_id)
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
    unless ks.source.to_s == 'grimoire'
      return render json: { error: 'Só é possível remover magias registradas via expansão do grimório.' },
                    status: :unprocessable_entity
    end
    sheet = sk.sheet
    spell_id = ks.spell_id
    ks.destroy!
    SheetPreparedSpell.where(sheet_id: sheet.id, spell_id: spell_id).delete_all
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  private

  def current_user_sheet_klass
    sheet_klass_id = params[:sheet_klass_id] || params.dig(:sheet_known_spell, :sheet_klass_id)
    if sheet_klass_id.present?
      sk = SheetKlass.find(sheet_klass_id)
      raise StandardError, 'Forbidden' unless sk.sheet.character.user_id == @current_user.id
      return sk
    end

    sheet_id = params[:sheet_id] || params.dig(:sheet_known_spell, :sheet_id)
    klass_api = params[:klass_api_index] || params.dig(:sheet_known_spell, :klass_api_index)
    if sheet_id.present? && klass_api.present?
      sheet = Sheet.find(sheet_id)
      raise StandardError, 'Forbidden' unless sheet.character.user_id == @current_user.id
      return sheet.sheet_klasses.joins(:klass).find_by!(klasses: { api_index: klass_api.to_s })
    end

    raise StandardError, 'sheet_klass_id ou sheet_id+klass_api_index obrigatório'
  end
end
