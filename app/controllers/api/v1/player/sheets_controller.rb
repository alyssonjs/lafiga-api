class Api::V1::Player::SheetsController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet, only: [:show, :update, :destroy]

  def index
    sheets = @current_user.sheets
    render json: {sheets: sheets}, status: 200
  end
  
  def show
    render json: {sheet: @sheet}, status: 200
  end

  def summary
    sheet = sheets_scope_for_current_user.find(params[:id])
    service = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: (params[:sync] != 'false'))
    if service.success?
      render json: { summary: service.result }, status: :ok
    else
      render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def assign_background
    sheet = @current_user.sheets.find(params[:id])
    service = BackgroundAssignmentService.call(
      sheet: sheet,
      key: params[:key],
      choices: params[:choices] || {}
    )
    if service.success?
      render json: { background: service.result }, status: :ok
    else
      render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def assign_feat
    sheet = @current_user.sheets.find(params[:id])
    service = FeatAssignmentService.call(
      sheet: sheet,
      feat_id: params[:feat_id],
      level_gained: params[:level_gained] || 1,
      choices: params[:choices] || {}
    )
    if service.success?
      render json: { feat: service.result }, status: :ok
    else
      render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def available_feats
    # Use database feats first, fallback to FeatRules for backward compatibility
    db_feats = Feat.all.index_by(&:api_index)
    feat_rules = FeatRules.all
    
    # Combine database feats with FeatRules fallback
    all_feat_ids = (db_feats.keys + feat_rules.keys).uniq
    
    feats = all_feat_ids.map do |feat_id|
      # Prefer database feat if available
      if db_feats[feat_id]
        feat = db_feats[feat_id]
        {
          id: feat.api_index,
          name: feat.name,
          description: feat.description,
          prerequisites: feat.prerequisites || {},
          ability_bonuses: feat.ability_bonuses || {},
          proficiency_bonuses: feat.proficiency_bonuses || {},
          cantrips: feat.cantrips || {},
          spells: feat.spells || {},
          features: feat.features || {},
          special_rules: feat.special_rules || {}
        }
      else
        # Fallback to FeatRules
        feat_data = feat_rules[feat_id]
        {
          id: feat_id,
          name: feat_data[:name],
          description: feat_data[:description],
          prerequisites: feat_data[:prerequisites] || {},
          ability_bonuses: feat_data[:ability_bonuses] || {},
          proficiency_bonuses: feat_data[:proficiency_bonuses] || {},
          cantrips: feat_data[:cantrips] || {},
          spells: feat_data[:spells] || {},
          features: feat_data[:features] || {},
          special_rules: {}
        }
      end
    end
    
    render json: { feats: feats }, status: :ok
  end

  def create
    # Processar o payload e extrair dados para as novas colunas
    processed_params = process_sheet_params(sheet_params)
    
    @sheet = Sheet.new(processed_params)
    
    if @sheet.save
      render json: @sheet, status: :created
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    # Processar o payload e extrair dados para as novas colunas
    processed_params = process_sheet_params(sheet_params)
    
    if @sheet.update(processed_params)
      render json: {sheet: @sheet}, status: 200 
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sheet.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sheet
    # DM/Admin (criterio canonico Group.user_is_dm?) pode acessar sheets de
    # qualquer player — fluxo do Mestre editando ficha importada via wizard de
    # edicao (PATCH /sheets/:id para HP, summary, etc.). Player comum continua
    # restrito ao proprio escopo via `current_user.sheets`.
    @sheet = sheets_scope_for_current_user.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def sheets_scope_for_current_user
    return Sheet.all if Group.user_is_dm?(@current_user)

    @current_user.sheets
  end

  def sheet_params
    # Phase 10 — adicionado `coins` (jsonb cp/sp/ep/gp/pp). A coluna existe no
    # schema desde 20260417120000, mas o controller nao permitia ainda — sem
    # essa permissao, qualquer PATCH com `sheet: { coins: {...} }` era
    # silenciosamente descartado. Foi um dos vetores do Bug 8 (nenhum
    # personagem tinha dinheiro apos o provisioning).
    params.require(:sheet).permit(
      :character_id,
      :race_id,
      :sub_race_id,
      :str, :dex, :con, :int, :wis, :cha,
      :hp_max, :hp_current, :temp_hp,
      coins: %i[cp sp ep gp pp],
      metadata: {}
    )
  end

  def process_sheet_params(params)
    # Phase 10 — bug critico (causou perda total de metadata em PATCH parcial):
    # antes este metodo sempre setava `processed[:metadata] = metadata`, e
    # quando o cliente enviava um PATCH sem `metadata` (ex.: so para atualizar
    # `coins` ou `hp_current`), `params[:metadata]` ficava nil → vinha `{}` →
    # sobrescrevia o metadata real com hash vazio. Foi assim que o pos-step
    # de hidratacao de coins do `provision-imported-as-bob.ts` apagou
    # `class_choices`, `race_choices`, `class_summary`, etc das fichas P81.
    metadata_provided = params.key?(:metadata)
    metadata = params[:metadata] || {}
    processed = params.except(:metadata)
    
    # Processar alignment
    if metadata['alignment'].present?
      alignment = Alignment.find_by(api_index: metadata['alignment']['index'])
      processed[:alignment_id] = alignment&.id
    end
    
    # Processar background
    if metadata['background_key'].present?
      background = Background.find_by(api_index: metadata['background_key'])
      processed[:background_id] = background&.id
      processed[:background_key] = metadata['background_key']
    end
    
    # Processar current_level
    if metadata['current_level'].present?
      processed[:current_level] = metadata['current_level']
    end
    
    # Processar race_choices
    if metadata['race_choices'].present?
      processed[:race_choices] = metadata['race_choices']
    end
    
    # Processar class_choices
    if metadata['class_choices'].present?
      processed[:class_choices] = metadata['class_choices']
    end
    
    # Processar summaries
    if metadata['race_summary'].present?
      processed[:race_summary] = metadata['race_summary']
    end
    
    if metadata['class_summary'].present?
      processed[:class_summary] = metadata['class_summary']
    end
    
    if metadata['background_summary'].present?
      processed[:background_summary] = metadata['background_summary']
    end
    
    if metadata['features_by_level'].present?
      processed[:features_by_level] = metadata['features_by_level']
    end
    
    # Processar race_bonuses_applied
    if metadata['race_bonuses_applied'].present?
      processed[:race_bonuses_applied] = metadata['race_bonuses_applied']
    end
    
    # Manter metadata original para compatibilidade (pode ser removido depois).
    # Phase 10 — APENAS quando o cliente realmente enviou `metadata` no body;
    # PATCH parcial (so `coins` / so `hp_current`) NAO deve zerar metadata.
    processed[:metadata] = metadata if metadata_provided

    processed
  end
end
