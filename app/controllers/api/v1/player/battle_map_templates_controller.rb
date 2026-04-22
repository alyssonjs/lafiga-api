class Api::V1::Player::BattleMapTemplatesController < ApplicationController
  before_action :authorize_request

  # GET /api/v1/player/battle_map_templates
  # Lista templates pre-prontos do BattleMap (vindos de
  # config/battle_map_templates.yml).
  def index
    render json: { templates: BattleMapTemplatesCatalog.all }, status: 200
  end

  # POST /api/v1/player/battle_map_templates/:slug/instantiate
  # Cria um BattleMap concreto para o user a partir do template.
  # Body opcional: { name, group_id }.
  def instantiate
    template = BattleMapTemplatesCatalog.find(params[:slug])
    return render(json: { error: 'Template nao encontrado' }, status: :not_found) unless template

    name = params.dig(:battle_map, :name).presence || template['name']
    group_id = params.dig(:battle_map, :group_id).presence

    cells = BattleMapTemplatesCatalog.materialize_cells(template)
    map = BattleMap.new(
      user_id: @current_user.id,
      group_id: group_id,
      name: name,
      width: template['width'].to_i,
      height: template['height'].to_i,
      cell_size_px: 32,
      cells: cells,
      tokens: [],
      fog: nil,
      schema_version: 1,
    )

    if map.save
      render json: { battle_map: BattleMapSerializer.serialize(map, mode: :full) }, status: :created
    else
      render json: { errors: map.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
