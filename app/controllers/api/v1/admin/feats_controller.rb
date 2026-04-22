class Api::V1::Admin::FeatsController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_feat, only: [:show, :update, :destroy]

  # GET /api/v1/admin/feats
  def index
    scope = Feat.all
    scope = search_scope(scope, params[:q] || params[:search])
    scope = scope.order(:name).limit(500)
    render json: { feats: scope.map { |f| feat_payload(f) } }, status: :ok
  end

  # GET /api/v1/admin/feats/:id
  def show
    render json: { feat: feat_payload(@feat) }, status: :ok
  end

  # POST /api/v1/admin/feats
  def create
    attrs = build_attrs(permitted_attrs)
    @feat = Feat.new(attrs)
    if @feat.save
      render json: { feat: feat_payload(@feat) }, status: :created
    else
      render json: { errors: @feat.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/admin/feats/:id
  def update
    if @feat.update(build_attrs(permitted_attrs))
      render json: { feat: feat_payload(@feat) }, status: :ok
    else
      render json: { errors: @feat.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/feats/:id
  def destroy
    if @feat.sheet_feats.exists?
      render json: {
        error: 'feat_in_use',
        sheets: @feat.sheets.pluck(:id),
      }, status: :unprocessable_entity
    else
      @feat.destroy
      head :no_content
    end
  end

  private

  def set_feat
    @feat = Feat.find_by(api_index: params[:id]) || Feat.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def search_scope(scope, q)
    return scope if q.blank?
    term = "%#{I18n.transliterate(q.to_s.downcase)}%"
    scope.where('lower(name) LIKE ? OR lower(api_index) LIKE ?', term, term)
  end

  def permitted_attrs
    params.require(:feat).permit(
      :name, :api_index, :description,
      { prerequisites: {} },
      { ability_bonuses: {} },
      { proficiency_bonuses: {} },
      { features: {} },
      { cantrips: {} },
      { spells: {} },
      { special_rules: {} },
      :prerequisites_raw, :ability_bonuses_raw, :proficiency_bonuses_raw,
      :features_raw, :cantrips_raw, :spells_raw, :special_rules_raw
    )
  end

  # Coloca em formato de coluna do Feat (que armazena alguns campos como
  # texto JSON) — o front consome via `mapApiFeatToFeat` que aceita ambas
  # as formas (Hash ja decodificada ou string JSON).
  def build_attrs(raw)
    h = raw.to_h
    JSON_FIELDS.each do |field|
      if h.key?(field) && h[field].is_a?(Hash)
        h[field] = h[field].to_json
      end
    end
    if h[:api_index].blank? && h[:name].present?
      h[:api_index] = derive_api_index(h[:name])
    end
    h
  end

  JSON_FIELDS = %i[prerequisites ability_bonuses proficiency_bonuses features cantrips spells special_rules].freeze

  def derive_api_index(name)
    'pt-' + I18n.transliterate(name.to_s).downcase
            .gsub(/[^a-z0-9\-\s]/, '')
            .strip
            .gsub(/\s+/, '-')
            .gsub(/-+/, '-')
  end

  # Mesma forma do public/feats#index para que admin/public devolvam o
  # mesmo shape (front pode reutilizar `mapApiFeatToFeat`).
  def feat_payload(feat)
    {
      id: feat.api_index || feat.id,
      api_index: feat.api_index,
      name: feat.name,
      description: feat.description,
      prerequisites: feat.prerequisites_data,
      ability_bonuses: feat.ability_bonuses_data,
      proficiency_bonuses: feat.proficiency_bonuses_data,
      features: feat.features_data,
      cantrips: parse_json(feat.cantrips),
      spells: parse_json(feat.spells),
      special_rules: parse_json(feat.special_rules),
    }
  end

  def parse_json(raw)
    return {} if raw.blank?
    return raw if raw.is_a?(Hash)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end
end
