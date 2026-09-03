# ⚠️ SÓ o Mestre — e não há irmão público. O NPC básico é bastidor de mesa: o
# jogador não escolhe um guarda de portão como escolhe um familiar.
class Api::V1::Admin::BasicNpcsController < ApplicationController
  ATTACK_PERMIT = [:name, :bonus, :damage, :notes].freeze

  before_action :authorize_site_wide_dm
  before_action :set_npc, only: [:show, :update, :destroy]

  def index
    scope = BasicNpc.busca(params[:q] || params[:search]).order(:name).limit(500)
    render json: { basic_npcs: scope.map { |n| linha(n) } }, status: :ok
  end

  def show
    render json: { basic_npc: linha(@npc) }, status: :ok
  end

  def create
    @npc = BasicNpc.new(permitted)
    if @npc.save
      render json: { basic_npc: linha(@npc) }, status: :created
    else
      render json: { errors: @npc.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @npc.update(permitted)
      render json: { basic_npc: linha(@npc) }, status: :ok
    else
      render json: { errors: @npc.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @npc.destroy
    head :no_content
  end

  private

  # Linha crua (o que o editor manipula) + a URL do token, que não é coluna.
  def linha(npc)
    npc.as_json(except: [:created_at, :updated_at])
       .merge('token_image_url' => npc.token_image_url)
  end

  def set_npc
    @npc = BasicNpc.find_by(slug: params[:id]) || BasicNpc.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end

  def permitted
    params.require(:basic_npc).permit(
      :slug, :name, :role, :notes, :hp, :ac, :initiative_bonus, :token_map_asset_id,
      { stats: {} }, { speed_modes: {} },
      # ⚠️ Array de HASHES: `attacks: []` cru DESCARTA o conteúdo e o NPC nasce
      # sem ataque nenhum — o mesmo defeito do catálogo de companheiros.
      { attacks: ATTACK_PERMIT }
    )
  end
end
