class Api::V1::Admin::RacesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_race, only: [:show, :update, :destroy]
  before_action :carrega_sub_racas, only: [:show]


  def index
    races = Race.order(:name)
    render json: { races: races.map { |r| serializa(r) } }, status: 200
  end

  def show
    render json: { race: serializa(@race), sub_races: @sub_races_json }, status: 200
  end

  # ⚠️ `rules_json` TEM de sair na leitura: sem ele o editor abre vazio e o
  # primeiro Guardar apaga o que o mestre já tinha configurado.
  def serializa(r)
    r.as_json(only: %i[id name api_index playable]).merge(
      'rules_json' => (r.rules_json || {}),
      # ⚠️ A base CRUA do YAML vai junto: é o que o editor compara para saber o
      # que o mestre TOCOU. Sem ela o formulário abriria vazio para as 13 do
      # livro e o primeiro save gravaria um overlay que apaga o catálogo.
      'rules_base' => (RaceRules.base_do_yaml(r.api_index) || {})
    )
  end

  def create
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    @race = Race.new(race_params)
    @race.rules_json = regras unless regras == :ausente

    if @race.save
      # 🐞 antes devolvia o objeto CRU: o cliente lia `data.race` e recebia
      # `undefined` — quem cria raça E sub-raça no mesmo gesto não tinha o
      # `race_id` para pendurar as sub-raças.
      render json: { race: serializa(@race) }, status: :created
    else
      render json: { errors: @race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    atributos = race_params.to_h
    atributos[:rules_json] = regras unless regras == :ausente

    if @race.update(atributos)
      render json: {race: @race}, status: 200 
    else
      render json: { errors: @race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @race.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_race
    @race = Race.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def race_params
    params.require(:race).permit(:name, :api_index, :playable)
  end

  # ⚠️ `rules_json` NÃO entra no `permit`: é jsonb de forma livre, e o
  # `permit` deixaria passar qualquer coisa. Passa pelo sanitizador, que é a
  # fronteira — forma errada aqui não quebra "a raça do mestre", quebra a
  # CRIAÇÃO DE PERSONAGEM, porque `RaceRules.apply` é lido em runtime.
  #
  # Devolve `[hash, erros]`; `:ausente` quando o pedido não fala de regras, que
  # é diferente de mandar `{}` (soltar tudo e voltar ao YAML).
  def regras_do_pedido
    bruto = params.require(:race)[:rules_json]
    return [:ausente, []] unless params.require(:race).key?(:rules_json)

    Races::RulesOverlay.sanitize(bruto)
  rescue ActionController::ParameterMissing
    [:ausente, []]
  end

  # ⚠️ A sub-raça leva a base CRUA do SEU nó, igual à raça. Sem ela o editor
  # abriria a sub-raça vazia e o primeiro Guardar gravaria um overlay que apaga
  # o que o livro dizia — e a sub-raça é onde mora quase toda a mecânica que
  # distingue um Anão da Colina de um das Montanhas.
  def carrega_sub_racas
    @sub_races_json = SubRace.where(race_id: @race.id).order(:name).map do |sr|
      Api::V1::Admin::SubRacesController.serializa(sr, @race.api_index)
    end
  end

end
