# frozen_string_literal: true

# O RELÓGIO DA VILA de um grupo (09/10; L0.3, plano B1 e B8). Devolve só a âncora e o agora do servidor: a hora, o
# Criador do dia, o período e a estação saem de conta no front (`relogioDoMundo.ts`), a mesma do `Mundo::Relogio`.
#
# Autorização por PERTENCER AO GRUPO (ou ser Mestre), como a carroça.
class Api::V1::Player::GroupMundosController < ApplicationController
  # Ler o mundo ALCANÇA o presente (avaliação preguiçosa, plano B1, L0.4): processa a agenda vencida, até este tanto de
  # eventos por requisição; o resto fica para a leitura seguinte (ou para o processo `relogio`, L0.5).
  LIMITE_POR_LEITURA = 50

  before_action :authorize_request
  before_action :set_group

  # GET /api/v1/player/groups/:group_id/mundo
  # → { mundo: { id, group_id, epoca_em, minuto_na_epoca, fator, pausado_desde } | null,
  #     agenda: { processados, em_dia } | null, agora_servidor }
  # `mundo` nulo = o grupo ainda não tem relógio (ele nasce com a vila, L1.7; no dev, `POST /api/v1/dev/mundos`).
  # `em_dia` falso = ficou agenda vencida para depois (o limite, ou outro avanço com o mundo nas mãos).
  def show
    agora = Time.current
    mundo = @group.mundo
    avanco = mundo && Mundo::Avanca.call(mundo, agora: agora, limite: LIMITE_POR_LEITURA)
    render json: {
      mundo: mundo&.para_api,
      agenda: avanco && { processados: avanco.processados, em_dia: avanco.em_dia },
      agora_servidor: agora.utc.iso8601(3),
    }, status: :ok
  end

  private

  def set_group
    @group = Group.find(params[:group_id])
    return if Group.user_is_dm?(@current_user)
    return if @group.characters.exists?(user_id: @current_user.id)

    render json: { errors: 'Not found' }, status: :not_found
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Not found' }, status: :not_found
  end
end
