class Api::V1::Admin::KlassesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_klass, only: [:show, :update, :destroy, :level_features, :update_level_feature, :destroy_level_feature]

  def index
    klasses = Klass.all
    render json: { klasses: klasses }, status: 200
  end

  def show
    render json: { klass: serializa(@klass) }, status: 200
  end

  # ⚠️ `rules_base` é a regra em CÓDIGO (`ClassRules::CLASS_RULES`), sem o
  # overlay. É contra ISTO que o editor decide o que o mestre TOCOU.
  #
  # A lição veio do editor de raças, onde custou quatro bugs mudos: sem a base,
  # o formulário compara contra `{}`, vê divergência em TODO campo e o primeiro
  # Guardar congela a classe numa cópia que deixa de acompanhar o catálogo. E
  # mandar a base JÁ SOBREPOSTA é pior: o que o mestre gravou pareceria igual à
  # base, não seria reemitido, e sumia no save seguinte.
  # ⚠️ As sub-classes vêm EMBUTIDAS, no espelho do `{race, sub_races}` das
  # raças: a página edita classe e arquétipos na mesma tela, e sem isto ela
  # precisaria de uma segunda chamada por sub-classe só para saber que elas
  # existem. `levels_base` vai junto pelo mesmo motivo do `rules_base`.
  def serializa(k)
    k.as_json.merge(
      'rules' => (k.read_attribute(:rules) || {}),
      'rules_base' => (ClassRules.find_from_rules_constant(k.api_index) || {}),
      'sub_klasses' => k.sub_klasses.order(:id).map { |sub| serializa_sub(sub, k.api_index) }
    )
  end

  def serializa_sub(sub, klass_idx)
    sub.as_json.merge(
      'levels_json' => sub.linhas_de_nivel,
      'levels_base' => Subclasses::YamlBase.linhas(klass_idx, sub.api_index)
    )
  end

  def create
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    @klass = Klass.new(klass_params)
    @klass.rules = regras unless regras == :ausente

    if @klass.save
      projeta_colunas!(@klass)
      # Envelopa em `{ klass: ... }` para o front consumir o mesmo shape
      # de `show`/`update` (`buildWizardClassOptionFromApi` espera o
      # registro raiz). Antes retornava `@klass` solto — exigia `as` ad-hoc
      # no caller.
      render json: { klass: serializa(@klass) }, status: :created
    else
      render json: { errors: @klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    regras, erros_regras = regras_do_pedido
    return render(json: { errors: erros_regras }, status: :unprocessable_entity) if erros_regras.any?

    atributos = klass_params.to_h
    atributos[:rules] = regras unless regras == :ausente

    if @klass.update(atributos)
      projeta_colunas!(@klass)
      repostas = repoe_fichas!(@klass)
      corpo = { klass: serializa(@klass) }
      corpo[:sheets_resynced] = repostas if repostas
      render json: corpo, status: 200
    else
      render json: { errors: @klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @klass.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def level_features
    result = Admin::LevelFeatureEditor.for_klass(@klass, level_feature_params)
    render json: level_feature_payload(result, :class_level), status: :created
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update_level_feature
    result = Admin::LevelFeatureEditor.for_klass(
      @klass,
      level_feature_params,
      feature_id: params[:feature_id],
    )
    render json: level_feature_payload(result, :class_level), status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy_level_feature
    result = Admin::LevelFeatureEditor.delete_for_klass(@klass, params[:feature_id], delete_level_feature_params)
    render json: {
      message: 'Caracteristica removida do nivel',
      feature: result.feature.as_json,
    }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_klass
    ident = params[:id].to_s
    @klass = ident.match?(/\A\d+\z/) ? Klass.find_by(id: ident) : nil
    @klass ||= Klass.find_by(api_index: ident)
    raise ActiveRecord::RecordNotFound, "Klass not found" unless @klass
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  # ⚠️ A ficha é um SNAPSHOT: a mecânica propaga sozinha (o produtor lê
  # `ClassRules` a cada summary), a VITRINE não. Sem isto o mestre edita a
  # classe, o personagem ganha a proficiência nova em combate e a ficha continua
  # a listar a lista velha — incoerente consigo mesma, sem erro em lugar nenhum.
  #
  # Inline e com `rescue`: gravar a regra é o que o mestre pediu e não pode
  # falhar por causa da propagação. O que ficar para trás é reconciliado pela
  # rake `dnd:resync_class_summaries`, que é idempotente.
  def repoe_fichas!(klass)
    return nil unless klass.saved_change_to_rules?

    Klasses::ResyncSummaries.call(klass_id: klass.id).mudadas
  rescue StandardError => e
    Rails.logger.warn("repoe_fichas! falhou para klass=#{klass.id}: #{e.message}")
    nil
  end

  # ⚠️ PROJEÇÃO das colunas derivadas. O nível da sub-classe vive em quatro
  # sítios e a coluna estava VAZIA nas 13 — é isso que mantinha sete guardas do
  # servidor inertes (`k.try(:subclass_level).to_i` → 0 passa sempre). Sem este
  # escritor, a classe editada pela página voltaria a divergir no primeiro save:
  # a regra diria 3 e a coluna continuaria nula.
  #
  # `saving_throws` entra pela mesma razão e é mais óbvio ainda: a coluna guarda
  # "Força" e a regra guarda "FOR", sem tradutor entre as duas grafias. Medido:
  # a coluna não tem leitor (`build_saving_throws` lê a REGRA), então alinhá-la
  # não muda ficha nenhuma — só para de mentir para quem a ler depois.
  def projeta_colunas!(klass)
    regra = ClassRules.find(klass.api_index) || {}
    colunas = {}

    nivel = (regra.dig(:subclass, :choose_level) || regra.dig('subclass', 'choose_level')).to_i
    colunas[:subclass_level] = nivel if nivel.positive? && klass.subclass_level.to_i != nivel

    testes = Array(regra[:saving_throws] || regra['saving_throws']).map(&:to_s)
    colunas[:saving_throws] = testes if testes.any? && Array(klass.saving_throws).map(&:to_s) != testes

    klass.update_columns(colunas) if colunas.any?
  rescue StandardError => e
    # A projeção é derivada: falhar nela não pode derrubar a gravação da regra,
    # que é o que o mestre pediu. A rake `dnd:backfill_subclass_level` reconcilia.
    Rails.logger.warn("projeta_colunas! falhou para klass=#{klass.id}: #{e.message}")
  end

  def klass_params
    # Adicionados (migration `add_description_and_metadata_to_klasses`):
    # - `description`: rich-text vindo do `RichTextEditor` do front (aba
    #   "Historia" no painel de detalhe).
    # - `primary_ability`: habilidade primária (string livre).
    # - `saving_throws`: array de strings (proficiências em ST).
    # - `short_description` (`add_short_description_to_klasses`): tagline
    #   exibida no cabecalho do painel.
    # Antes destes permits o modal `ClassFormModal.tsx` coletava esses
    # campos mas eles eram silenciosamente descartados.
    params.require(:klass).permit(
      :name,
      :api_index,
      :hit_die,
      :spellcasting_ability,
      :primary_ability,
      :description,
      :short_description,
      :progression_table,
      :subclass_level,
      :playable,
      saving_throws: [],
    )
  end

  # ⚠️ `rules` NÃO entra no `permit`.
  #
  # 🐞 Entrava como `rules: {}` — forma livre, sem validação nenhuma. E
  # `KlassDbRulesContract`, que existe e define as chaves obrigatórias, tinha
  # ZERO chamadas no caminho de escrita: só uma rake manual e o próprio spec.
  # Somado ao replace-all que `ClassRules.find` fazia, um PATCH com meia classe
  # apagava a outra metade para todos os personagens dela, em silêncio.
  #
  # Agora passa pelo sanitizador, que é a fronteira: forma errada aqui não
  # quebra "a classe do mestre", quebra a CRIAÇÃO DE PERSONAGEM, porque
  # `ClassRules.find` é lido em runtime por 33 pontos.
  #
  # Devolve `[hash, erros]`; `:ausente` quando o pedido não fala de regras, que
  # é diferente de mandar `{}` (soltar tudo e voltar à regra em código).
  def regras_do_pedido
    return [:ausente, []] unless params.require(:klass).key?(:rules)

    Klasses::RulesOverlay.sanitize(params.require(:klass)[:rules])
  rescue ActionController::ParameterMissing
    [:ausente, []]
  end

  def level_feature_params
    params.require(:feature).permit(:level, :api_index, :name, :description)
  end

  def delete_level_feature_params
    return {} unless params[:feature].present?

    params.require(:feature).permit(:level)
  end

  def level_feature_payload(result, level_key)
    {
      level_key => result.level_record.as_json(include: { features: {} }),
      feature: result.feature.as_json,
    }
  end
end
