class Api::V1::Admin::SubRacesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sub_race, only: [:show, :update, :destroy]

  def index
    sub_races = SubRace.order(:name)
    render json: {sub_races: sub_races}, status: 200
  end

  def show
    render json: {sub_race: @sub_race}, status: 200
  end

  def create
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    @sub_race = SubRace.new(sub_race_params)
    @sub_race.rules_json = regras unless regras == :ausente

    if @sub_race.save
      render json: @sub_race, status: :created
    else
      render json: { errors: @sub_race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    atributos = sub_race_params.to_h
    atributos[:rules_json] = regras unless regras == :ausente

    if @sub_race.update(atributos)
      render json: {sub_race: @sub_race}, status: 200
    else
      render json: { errors: @sub_race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sub_race.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sub_race
    @sub_race = SubRace.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def sub_race_params
    params.require(:sub_race).permit(:name, :race_id, :api_index, :playable)
  end

  # ⚠️ `rules_json` NÃO entra no `permit`: é jsonb de forma livre, e o
  # `permit` deixaria passar qualquer coisa. Passa pelo sanitizador, que é a
  # fronteira — forma errada aqui não quebra "a raça do mestre", quebra a
  # CRIAÇÃO DE PERSONAGEM, porque `RaceRules.apply` é lido em runtime.
  #
  # Devolve `[hash, erros]`; `:ausente` quando o pedido não fala de regras, que
  # é diferente de mandar `{}` (soltar tudo e voltar ao YAML).
  def regras_do_pedido
    bruto = params.require(:sub_race)[:rules_json]
    return [:ausente, []] unless params.require(:sub_race).key?(:rules_json)

    Races::RulesOverlay.sanitize(bruto)
  rescue ActionController::ParameterMissing
    [:ausente, []]
  end
end
