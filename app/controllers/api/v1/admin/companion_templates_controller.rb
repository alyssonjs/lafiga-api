# Compendio de COMPANHEIROS — so o Mestre cria/edita (decisao do DM em 02/09).
# Mesmo gate dos itens magicos: `authorize_site_wide_dm`, nao `admin` puro,
# senao o DM leva 401 e o apiClient desloga a sessao inteira.
class Api::V1::Admin::CompanionTemplatesController < ApplicationController
  # ⚠️ Array de HASHES em strong params: `attacks: []` sozinho DESCARTA o
  # conteudo (Rails so aceita escalares em array cru). Listar as chaves.
  # `ability`/`proficient`: de onde o bonus SAI (FOR ou DES + proficiencia), em
  # vez de um numero copiado que fica errado assim que o atributo muda.
  ATTACK_PERMIT = [:name, :attackBonus, :attack_bonus, :damage, :damageType,
                   :damage_type, :range, :notes, :ability, :proficient].freeze

  # ⚠️ `mechanics` e um hash ANINHADO dentro de um array de hashes. Sem listar
  # as chaves dele, o Rails descarta o bloco inteiro e a acao volta a ser so
  # prosa — o defeito que o F2a existe para fechar.
  MECHANICS_PERMIT = [
    :saveAbility, :save_ability, :saveDc, :save_dc, :halfOnSave, :half_on_save,
    { damage: [:dice, :type] },
    { area: [:shape, :sizeFt, :size_ft, :widthFt, :width_ft] },
  ].freeze

  SPECIAL_ACTION_PERMIT = [:name, :actionCost, :action_cost, :description,
                           :usesOwnerAction, :uses_owner_action, :recharge,
                           { mechanics: MECHANICS_PERMIT }].freeze

  FLAGS_PERMIT = [:use_owner_proficiency, :scales_with_owner_level,
                  :owner_level_required, :shares_senses, :deliver_touch_spells,
                  :temporary, :duration, :requires_concentration].freeze

  before_action :authorize_site_wide_dm
  before_action :set_template, only: [:show, :update, :destroy]

  def index
    scope = CompanionTemplate.with_attached_token_image
    scope = scope.do_tipo(params[:companion_type] || params[:type])
    scope = scope.busca(params[:q] || params[:search])
    scope = scope.order(:companion_type, :name).limit(500)
    render json: { companion_templates: scope.map { |t| linha(t) } }, status: :ok
  end

  def show
    render json: { companion_template: linha(@template) }, status: :ok
  end

  def create
    @template = CompanionTemplate.new(permitted)
    anexar_token_image(@template)
    resolver_conflito_de_token(@template)
    if @template.save
      render json: { companion_template: linha(@template) }, status: :created
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    anexar_token_image(@template)
    @template.assign_attributes(permitted)
    resolver_conflito_de_token(@template)
    if @template.save
      render json: { companion_template: linha(@template) }, status: :ok
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    head :no_content
  end

  private

  # O PNG chega em multipart, fora do corpo JSON. `remove_token_image` é o
  # caminho explícito para APAGAR — sem ele, tirar a imagem seria impossível:
  # um campo ausente significa "não mexi", não "apague".
  def anexar_token_image(template)
    if ActiveModel::Type::Boolean.new.cast(params[:remove_token_image])
      template.token_image.purge_later if template.token_image.attached?
      return
    end

    arquivo = params[:token_image] || params.dig(:companion_template, :token_image)
    return if arquivo.blank?

    template.token_image.attach(arquivo)
    # ⚠️ Uma fonte por vez: subir um PNG desfaz a escolha da biblioteca, senão
    # ficariam duas verdades e a precedência decidiria em silêncio qual vence.
    template.token_map_asset_id = nil
  end

  # Escolher da biblioteca é o inverso: apaga o anexo próprio.
  def resolver_conflito_de_token(template)
    return unless template.token_map_asset_id_changed? && template.token_map_asset_id.present?

    template.token_image.purge_later if template.token_image.attached?
  end

  # Linha crua (o que o editor edita) + a URL do token, que não é coluna.
  def linha(template)
    template.as_json(except: [:created_at, :updated_at])
            .merge('token_image_url' => template.token_image_url)
  end

  def set_template
    @template = CompanionTemplate.find_by(slug: params[:id]) || CompanionTemplate.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end

  def permitted
    params.require(:companion_template).permit(
      :slug, :name, :companion_type, :origin, :origin_spell_id,
      :origin_class_feature, :creature_type, :size, :ac, :hp_max, :speed,
      :prof_bonus, :carry_capacity, :description, :source, :token_map_asset_id,
      { stats: {} }, { tags: [] }, { speed_modes: {} },
      { skill_proficiencies: [] }, { save_proficiencies: [] },
      { attacks: ATTACK_PERMIT },
      { special_actions: SPECIAL_ACTION_PERMIT },
      { flags: FLAGS_PERMIT }
    )
  end
end
