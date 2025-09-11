class Api::V1::Public::ClassRulesController < ApplicationController
  def index
    render json: { class_rules: ClassRules.rules, dictionaries: ClassRules.dictionaries }, status: :ok
  end

  def show
    rule = ClassRules.find(params[:id])
    return render json: { error: 'not found' }, status: :not_found unless rule
    render json: { class_rule: rule }, status: :ok
  end

  # POST /api/v1/public/class_rules/apply
  # body: { selection: { klass_id, level, skills_selected: [], instruments_selected: [], picks: {...} } }
  def apply
    selection = params.require(:selection).permit!
    result = ClassRules.apply(selection.to_h.symbolize_keys)
    render json: { result: result }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
