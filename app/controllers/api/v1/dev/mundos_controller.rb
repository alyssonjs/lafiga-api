# frozen_string_literal: true

# Ferramentas de DESENVOLVIMENTO do relógio da vila (09/10; L0.3). As rotas só existem fora de produção
# (`config/routes.rb`); mesmo assim pedem login e acesso ao grupo (Mestre ou quem tem personagem nele).
class Api::V1::Dev::MundosController < ApplicationController
  # o relógio novo começa ao meio-dia do dia 1: avançar 8 h leva ao anoitecer (o roteiro do L0.3)
  MEIO_DIA = 12 * 60
  # avançar no máximo um ano de jogo de uma vez
  MAX_HORAS = 24 * 480

  before_action :authorize_request

  # POST /api/v1/dev/mundos   body: { group_id, minuto? }
  # Cria o relógio do grupo; se ele já existe, devolve o que há.
  def create
    group = grupo_acessivel(params[:group_id])
    return render json: { errors: 'Not found' }, status: :not_found unless group

    agora = Time.current
    criado = group.mundo.nil?
    mundo = group.mundo || group.create_mundo!(epoca_em: agora, minuto_na_epoca: Integer(params.fetch(:minuto, MEIO_DIA)), fator: 40)
    render json: resposta(mundo, agora), status: criado ? :created : :ok
  rescue ArgumentError, TypeError
    render json: { errors: '`minuto` deve ser um inteiro.' }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/v1/dev/mundos/:id/avancar   body: { horas }
  # Um SALTO de propósito, para ver a noite cair sem esperar.
  def avancar
    mundo = Mundo.find_by(id: params[:id])
    return render json: { errors: 'Not found' }, status: :not_found unless mundo && grupo_acessivel(mundo.group_id)

    horas = Integer(params[:horas])
    unless horas.between?(1, MAX_HORAS)
      return render json: { errors: "`horas` deve ir de 1 a #{MAX_HORAS}." }, status: :unprocessable_entity
    end

    agora = Time.current
    mundo.avanca!(agora: agora, minutos: horas * 60)
    render json: resposta(mundo, agora), status: :ok
  rescue ArgumentError, TypeError
    render json: { errors: "`horas` deve ser um inteiro de 1 a #{MAX_HORAS}." }, status: :unprocessable_entity
  end

  private

  def resposta(mundo, agora)
    { mundo: mundo.para_api, agora_servidor: agora.utc.iso8601(3) }
  end

  def grupo_acessivel(id)
    group = Group.find_by(id: id)
    return nil unless group
    return group if Group.user_is_dm?(@current_user) || group.characters.exists?(user_id: @current_user.id)

    nil
  end
end
