class Api::V1::Player::SheetKlassesController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet_klass, only: [:show, :update, :destroy]

  def index
    sheet_klasses = @current_user.sheet_klasses
    render json: {sheet_klasses: sheet_klasses}, status: 200
  end
  
  def show
    render json: {sheet_klass: @sheet_klass}, status: 200
  end

  def create
    permitted = sheet_klass_params
    desired_level = (permitted[:level] || 1).to_i
    sheet = @current_user.sheets.find(permitted[:sheet_id])
    sub_id = resolve_sub_klass_identifier(permitted[:sub_klass_id], klass_id: permitted[:klass_id])

    # Se for nível > 1, use LevelUpService para aplicar progressão e conceder features
    if desired_level > 1
      service = LevelUpService.call(sheet_id: sheet.id, klass_id: permitted[:klass_id], levels: desired_level, sub_klass_id: sub_id)
      if service.success?
        sk = sheet.sheet_klasses.find_by!(klass_id: permitted[:klass_id])
        render json: sk, status: :created
      else
        render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
      end
      return
    end

    # Caso nível 1 (ou ausente), cria registro simples e concede features de nível 1
    @sheet_klass = SheetKlass.new(sheet_id: sheet.id, klass_id: permitted[:klass_id], sub_klass_id: sub_id, level: [desired_level, 1].max)
    if @sheet_klass.save
      FeatureGrantService.call(sheet: sheet, klass: @sheet_klass.klass, from_level: 0, to_level: @sheet_klass.level)
      persist_known_spells_from_metadata(sheet: sheet, sheet_klass: @sheet_klass, to_level: @sheet_klass.level)
      render json: @sheet_klass, status: :created
    else
      render json: { errors: @sheet_klass.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    permitted = sheet_klass_params
    new_level = permitted[:level].present? ? permitted[:level].to_i : @sheet_klass.level
    sub_klass_id = resolve_sub_klass_identifier(permitted[:sub_klass_id], klass_id: @sheet_klass.klass_id)

    Rails.logger.info "SheetKlass Update: current_level=#{@sheet_klass.level}, new_level=#{new_level}, delta=#{new_level - @sheet_klass.level}"

    # Se aumento de nível foi solicitado, use LevelUpService para aplicar delta
    if new_level > @sheet_klass.level
      delta = new_level - @sheet_klass.level
      Rails.logger.info "Calling LevelUpService with delta=#{delta}, sub_klass_id=#{sub_klass_id}"
      service = LevelUpService.call(sheet_id: @sheet_klass.sheet_id, klass_id: @sheet_klass.klass_id, levels: delta, sub_klass_id: sub_klass_id)
      if service.success?
        @sheet_klass.reload
        Rails.logger.info "LevelUpService successful, new level=#{@sheet_klass.level}"
        render json: { sheet_klass: @sheet_klass }, status: 200
      else
        Rails.logger.error "LevelUpService failed: #{service.errors.full_messages}"
        render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
      end
      return
    end

    # Atualizações sem incremento de nível (ex.: apenas sub_klass_id quando já elegível)
    update_attrs = permitted.to_h.symbolize_keys
    update_attrs[:sub_klass_id] = sub_klass_id if permitted[:sub_klass_id].present?
    if @sheet_klass.update(update_attrs)
      # Garantir concessão de features de subclasse quando definida após atingir o nível elegível
      if sub_klass_id.present?
        FeatureGrantService.call(sheet: @sheet_klass.sheet, klass: @sheet_klass.klass, from_level: 0, to_level: @sheet_klass.level)
      end
      render json: {sheet_klass: @sheet_klass}, status: 200 
    else
      render json: { errors: @sheet_klass.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sheet_klass.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sheet_klass
    @sheet_klass = @current_user.sheet_klasses.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def sheet_klass_params
    params.require(:sheet_klass).permit(:sheet_id, :klass_id, :sub_klass_id, :level)
  end

  # Accepts numeric ID or slug (api_index). If a slug is given, resolves to ID.
  def resolve_sub_klass_identifier(raw, klass_id: nil)
    return nil if raw.blank?
    str = raw.to_s
    if str.match?(/\A\d+\z/)
      return str.to_i
    end
    scope = SubKlass.all
    scope = scope.where(klass_id: klass_id) if klass_id.present?
    sub = scope.find_by!(api_index: str)
    sub.id
  end

  def persist_known_spells_from_metadata(sheet:, sheet_klass:, to_level:)
    per = (sheet.metadata || {}).dig('class_choices', 'per_level') || {}
    (1..to_level.to_i).each do |lvl|
      row = per[lvl.to_s] || {}
      Array(row['cantrips']).each do |sp|
        sid = (sp['id'] || sp[:id]).to_i
        next if sid.zero?
        SheetKnownSpell.find_or_create_by!(sheet_klass_id: sheet_klass.id, spell_id: sid)
      end
      Array(row['spells']).each do |sp|
        sid = (sp['id'] || sp[:id]).to_i
        next if sid.zero?
        SheetKnownSpell.find_or_create_by!(sheet_klass_id: sheet_klass.id, spell_id: sid)
      end
    end
  rescue => e
    Rails.logger.warn("persist_known_spells_from_metadata skipped: #{e.message}")
  end
end
