class Api::V1::Public::FeatsController < ApplicationController
  # GET /api/v1/public/feats
  # Same payload as player/sheets#available_feats (read-only, no auth).
  def index
    render json: { feats: public_feats_payload }, status: :ok
  end

  # GET /api/v1/public/feats/:id
  def show
    list = public_feats_payload
    id = params[:id].to_s
    row = list.find { |f| f[:id].to_s == id }
    return render json: { error: 'not found' }, status: :not_found unless row

    render json: { feat: row }, status: :ok
  end

  private

  def public_feats_payload
    db_feats = Feat.all.index_by(&:api_index)
    feat_rules = FeatRules.all
    # ⚠️ A união banco + FeatRules mostrava talentos DEPRECIADOS como se fossem
    # novos: "Durável" ao lado de "Resistente" (o mesmo talento sob duas chaves)
    # e "Especialista em Armadura" ao lado de "Proteção Pesada". Eles existem
    # para fichas legadas resolverem, não para o mestre escolher — quem é só do
    # FeatRules e tem `deprecated_for` fica de fora da vitrine.
    so_do_ruby = feat_rules.keys - db_feats.keys
    vivos_do_ruby = so_do_ruby.reject { |k| feat_rules[k][:deprecated_for].present? }
    all_feat_ids = (db_feats.keys + vivos_do_ruby).uniq

    all_feat_ids.map do |feat_id|
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
  end
end
