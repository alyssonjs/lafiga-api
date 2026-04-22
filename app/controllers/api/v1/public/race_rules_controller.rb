class Api::V1::Public::RaceRulesController < ApplicationController
  def index
    render json: {
      race_rules: RaceRules.rules,
      trait_definitions: RaceRules.trait_definitions
    }, status: :ok
  end

  def show
    rule = RaceRules.find(params[:id])
    return render json: { error: 'not found' }, status: :not_found unless rule

    render json: { race_rule: rule }, status: :ok
  end

  # POST /api/v1/public/race_rules/apply
  # body: { selection: { race_id, subrace_id, choices: {...} } }
  def apply
    selection = params.require(:selection).permit!
    result = RaceRules.apply(selection.to_h.symbolize_keys)
    render json: { result: result }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
