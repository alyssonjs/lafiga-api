class Api::V1::Admin::SubRacesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sub_race, only: [:show, :update, :destroy]

  def index
    sub_races = SubRace.order(:name)
    render json: {sub_races: sub_races}, status: 200
  end

  def show
    render json: { sub_race: self.class.serializa(@sub_race) }, status: 200
  end

  # ⚠️ `rules_json` E `rules_base` na leitura. O primeiro é o que o mestre
  # gravou; o segundo é o nó CRU do YAML, contra o qual o editor decide o que
  # DIVERGE. Sem o segundo, `serializar` vê divergência em todo campo e congela
  # a sub-raça numa cópia que deixa de acompanhar o catálogo.
  def self.serializa(sr, api_index_da_raca = nil)
    slug = api_index_da_raca || sr.race&.api_index
    sr.as_json(only: %i[id name api_index playable race_id]).merge(
      'rules_json' => (sr.rules_json || {}),
      'rules_base' => (RaceRules.base_do_yaml(slug, sr.api_index) || {})
    )
  end

  def create
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    @sub_race = SubRace.new(sub_race_params)
    @sub_race.rules_json = regras unless regras == :ausente

    if @sub_race.save
      render json: { sub_race: self.class.serializa(@sub_race) }, status: :created
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
      render json: { sub_race: self.class.serializa(@sub_race) }, status: 200
    else
      render json: { errors: @sub_race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  # ⚠️ Há FK de `sheets` para `sub_races`: apagar uma sub-raça em uso levantava
  # `InvalidForeignKey` e o `rescue` devolvia a mensagem crua do Postgres com
  # 404 — o mestre lia "não encontrado" para algo que existe e está em uso.
  # Agora recusa antes, dizendo quantas fichas dependem dela.
  def destroy
    em_uso = Sheet.where(sub_race_id: @sub_race.id).count
    if em_uso.positive?
      return render(
        json: { errors: ["#{@sub_race.name} está em uso por #{em_uso} ficha(s) e não pode ser removida."] },
        status: :unprocessable_entity
      )
    end

    @sub_race.destroy
    render json: { message: 'Deletado com sucesso' }, status: 200
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
