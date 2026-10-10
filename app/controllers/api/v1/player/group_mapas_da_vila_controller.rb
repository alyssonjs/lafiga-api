# frozen_string_literal: true

# A LISTA dos mapas da vila de um grupo (09/10; L1.2, plano B3): os mapas em blocos dos setores da campanha. Fica à
# parte da biblioteca de mapas de sempre (`GET /battle_maps`), que não os mostra: eles não têm `cells` e não se editam
# no Map Builder. O conteúdo de cada um vem da API de blocos (`GET /battle_maps/:id/blocos`).
#
# Autorização por PERTENCER AO GRUPO (ou ser Mestre), como o relógio (`GroupMundosController`).
class Api::V1::Player::GroupMapasDaVilaController < ApplicationController
  before_action :authorize_request
  before_action :set_group

  # GET /api/v1/player/groups/:group_id/mapas_da_vila?page=&per_page=
  # → { mapas_da_vila: [{ id, nome, colunas, linhas, semente, versao_do_gerador, versao_dos_biomas, lado, blocos,
  #                       blocos_no_mapa, setor: { id, chave, nome, tipo } | null, atualizado_em }],
  #     meta: { page, per_page, total } }
  # Na ordem da corrente de setores. `blocos` são os que já estão gravados; `blocos_no_mapa`, os que ele tem.
  def index
    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = [[params.fetch(:per_page, 50).to_i, 100].min, 1].max
    base = @group.battle_maps.where(armazenamento: 'blocos')
    total = base.count
    mapas = base.left_joins(:setor).includes(:setor)
                .order(Arel.sql('setores.ordem ASC NULLS LAST'), :id)
                .limit(per_page).offset((page - 1) * per_page).to_a
    gravados = MapaBloco.where(battle_map_id: mapas.map(&:id)).group(:battle_map_id).count

    render json: {
      mapas_da_vila: mapas.map { |mapa| item(mapa, gravados.fetch(mapa.id, 0)) },
      meta: { page: page, per_page: per_page, total: total },
    }, status: :ok
  end

  private

  def item(mapa, blocos)
    setor = mapa.setor
    {
      id: mapa.id,
      nome: mapa.name,
      colunas: mapa.width,
      linhas: mapa.height,
      semente: mapa.semente,
      versao_do_gerador: mapa.versao_do_gerador,
      versao_dos_biomas: mapa.versao_dos_biomas,
      lado: MapaBloco::LADO,
      blocos: blocos,
      blocos_no_mapa: MapaBloco.blocos_no_mapa(mapa),
      setor: setor && { id: setor.id, chave: setor.chave, nome: setor.nome, tipo: setor.tipo },
      atualizado_em: mapa.updated_at.utc.iso8601,
    }
  end

  def set_group
    @group = Group.find(params[:group_id])
    return if Group.user_is_dm?(@current_user)
    return if @group.characters.exists?(user_id: @current_user.id)

    render json: { errors: 'Not found' }, status: :not_found
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end
end
