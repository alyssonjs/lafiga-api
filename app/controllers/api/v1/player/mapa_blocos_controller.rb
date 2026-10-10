# frozen_string_literal: true

# A API de BLOCO do mapa da vila (09/10; L1.2, plano B3 e B8). O jogador carrega os blocos em volta de onde está: a
# janela de `raio` blocos em volta de (bc, bl), cortada pela borda do mapa. O `bloco_mudou` do canal do mapa diz qual
# bloco recarregar (com raio 0).
#
# Autorização: quem lê o mapa (`BattleMap#readable_by?`: o Mestre, o dono, quem tem personagem no grupo).
class Api::V1::Player::MapaBlocosController < ApplicationController
  RAIO_MAX = 2

  before_action :authorize_request
  before_action :set_mapa

  # GET /api/v1/player/battle_maps/:battle_map_id/blocos?bc=&bl=&raio=1
  # → { blocos: [{ bc, bl, versao, terreno, objetos }], meta: { lado, colunas, linhas, total } }
  def index
    bc = Integer(params.require(:bc))
    bl = Integer(params.require(:bl))
    raio = Integer(params.fetch(:raio, 1))
    unless raio.between?(0, RAIO_MAX)
      return render json: { errors: "`raio` deve ir de 0 a #{RAIO_MAX}." }, status: :unprocessable_entity
    end

    blocos = @mapa.mapa_blocos.na_janela(bc, bl, raio).to_a
    render json: {
      blocos: blocos.map(&:para_api),
      meta: { lado: MapaBloco::LADO, colunas: @mapa.width, linhas: @mapa.height, total: blocos.size },
    }, status: :ok
  rescue ArgumentError, TypeError, ActionController::ParameterMissing
    render json: { errors: '`bc` e `bl` são inteiros.' }, status: :unprocessable_entity
  end

  private

  def set_mapa
    @mapa = BattleMap.find_by(id: params[:battle_map_id])
    return render json: { errors: 'Not found' }, status: :not_found unless @mapa
    return render json: { errors: 'Sem permissão' }, status: :forbidden unless @mapa.readable_by?(@current_user)
    return if @mapa.blocos?

    render json: { errors: 'Este mapa não é em blocos.' }, status: :unprocessable_entity
  end
end
