class Api::V1::Admin::KlassesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_klass, only: [:show, :update, :destroy, :level_features, :update_level_feature, :destroy_level_feature]

  def index
    klasses = Klass.all
    render json: {klasses: klasses}, status: 200
  end
  
  def show
    render json: {klass: @klass}, status: 200
  end

  def create
    @klass = Klass.new(klass_params)

    if @klass.save
      # Envelopa em `{ klass: ... }` para o front consumir o mesmo shape
      # de `show`/`update` (`buildWizardClassOptionFromApi` espera o
      # registro raiz). Antes retornava `@klass` solto — exigia `as` ad-hoc
      # no caller.
      render json: { klass: @klass }, status: :created
    else
      render json: { errors: @klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @klass.update(klass_params)
      render json: {klass: @klass}, status: 200 
    else
      render json: { errors: @klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @klass.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def level_features
    result = Admin::LevelFeatureEditor.for_klass(@klass, level_feature_params)
    render json: level_feature_payload(result, :class_level), status: :created
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update_level_feature
    result = Admin::LevelFeatureEditor.for_klass(
      @klass,
      level_feature_params,
      feature_id: params[:feature_id],
    )
    render json: level_feature_payload(result, :class_level), status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy_level_feature
    result = Admin::LevelFeatureEditor.delete_for_klass(@klass, params[:feature_id], delete_level_feature_params)
    render json: {
      message: 'Caracteristica removida do nivel',
      feature: result.feature.as_json,
    }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_klass
    ident = params[:id].to_s
    @klass = ident.match?(/\A\d+\z/) ? Klass.find_by(id: ident) : nil
    @klass ||= Klass.find_by(api_index: ident)
    raise ActiveRecord::RecordNotFound, "Klass not found" unless @klass
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def klass_params
    # Adicionados (migration `add_description_and_metadata_to_klasses`):
    # - `description`: rich-text vindo do `RichTextEditor` do front (aba
    #   "Historia" no painel de detalhe).
    # - `primary_ability`: habilidade primária (string livre).
    # - `saving_throws`: array de strings (proficiências em ST).
    # - `short_description` (`add_short_description_to_klasses`): tagline
    #   exibida no cabecalho do painel.
    # Antes destes permits o modal `ClassFormModal.tsx` coletava esses
    # campos mas eles eram silenciosamente descartados.
    params.require(:klass).permit(
      :name,
      :api_index,
      :hit_die,
      :spellcasting_ability,
      :primary_ability,
      :description,
      :short_description,
      :subclass_level,
      rules: {},
      saving_throws: [],
    )
  end

  def level_feature_params
    params.require(:feature).permit(:level, :api_index, :name, :description)
  end

  def delete_level_feature_params
    return {} unless params[:feature].present?

    params.require(:feature).permit(:level)
  end

  def level_feature_payload(result, level_key)
    {
      level_key => result.level_record.as_json(include: { features: {} }),
      feature: result.feature.as_json,
    }
  end
end
