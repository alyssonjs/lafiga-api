# Compendio de COMPANHEIROS — so o Mestre cria/edita (decisao do DM em 02/09).
# Mesmo gate dos itens magicos: `authorize_site_wide_dm`, nao `admin` puro,
# senao o DM leva 401 e o apiClient desloga a sessao inteira.
class Api::V1::Admin::CompanionTemplatesController < ApplicationController
  # ⚠️ Array de HASHES em strong params: `attacks: []` sozinho DESCARTA o
  # conteudo (Rails so aceita escalares em array cru). Listar as chaves.
  ATTACK_PERMIT = [:name, :attackBonus, :attack_bonus, :damage, :damageType,
                   :damage_type, :range, :notes].freeze

  SPECIAL_ACTION_PERMIT = [:name, :actionCost, :action_cost, :description,
                           :usesOwnerAction, :uses_owner_action, :recharge].freeze

  FLAGS_PERMIT = [:use_owner_proficiency, :scales_with_owner_level,
                  :owner_level_required, :shares_senses, :deliver_touch_spells,
                  :temporary, :duration, :requires_concentration].freeze

  before_action :authorize_site_wide_dm
  before_action :set_template, only: [:show, :update, :destroy]

  def index
    scope = CompanionTemplate.all
    scope = scope.do_tipo(params[:companion_type] || params[:type])
    scope = scope.busca(params[:q] || params[:search])
    scope = scope.order(:companion_type, :name).limit(500)
    render json: { companion_templates: scope.as_json(except: [:created_at, :updated_at]) }, status: :ok
  end

  def show
    render json: { companion_template: @template.as_json(except: [:created_at, :updated_at]) }, status: :ok
  end

  def create
    @template = CompanionTemplate.new(permitted)
    if @template.save
      render json: { companion_template: @template }, status: :created
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @template.update(permitted)
      render json: { companion_template: @template }, status: :ok
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    head :no_content
  end

  private

  def set_template
    @template = CompanionTemplate.find_by(slug: params[:id]) || CompanionTemplate.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end

  def permitted
    params.require(:companion_template).permit(
      :slug, :name, :companion_type, :origin, :origin_spell_id,
      :origin_class_feature, :creature_type, :size, :ac, :hp_max, :speed,
      :prof_bonus, :carry_capacity, :description, :source,
      { stats: {} }, { tags: [] },
      { attacks: ATTACK_PERMIT },
      { special_actions: SPECIAL_ACTION_PERMIT },
      { flags: FLAGS_PERMIT }
    )
  end
end
