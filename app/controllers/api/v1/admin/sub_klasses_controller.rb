class Api::V1::Admin::SubKlassesController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sub_klass, only: [:show, :update, :destroy, :level_features, :update_level_feature, :destroy_level_feature]

  def index
    sub_klasses = SubKlass.all
    render json: {sub_klasses: sub_klasses}, status: 200
  end

  def show
    render json: { sub_klass: serializa(@sub_klass) }, status: 200
  end

  # ⚠️ `levels_base` é a regra do LIVRO (o nó do YAML), sem o que o mestre
  # gravou. É contra ISTO que a página decide o que foi TOCADO, e é daqui que
  # sai o "restaurar nível do livro". A lição veio do editor de raças, onde
  # custou quatro bugs mudos: sem base, o formulário compara contra `{}`, vê
  # divergência em todo campo e o primeiro Guardar congela a sub-classe numa
  # cópia que deixa de acompanhar o catálogo.
  def serializa(sub)
    sub.as_json.merge(
      'levels_json' => sub.linhas_de_nivel,
      'levels_base' => Subclasses::YamlBase.linhas(sub.klass&.api_index, sub.api_index)
    )
  end

  def create
    @sub_klass = SubKlass.new(sub_klass_params)
    niveis, erros = niveis_do_pedido(@sub_klass)
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    unless niveis == :ausente
      @sub_klass.levels_json = niveis
      @sub_klass.edited_at = Time.current
    end

    if @sub_klass.save
      render json: { sub_klass: serializa(@sub_klass) }, status: :created
    else
      render json: { errors: @sub_klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    niveis, erros = niveis_do_pedido(@sub_klass)
    return render(json: { errors: erros }, status: :unprocessable_entity) if erros.any?

    atributos = sub_klass_params.to_h
    atributos['levels_json'] = niveis unless niveis == :ausente

    if atualiza!(atributos)
      render json: { sub_klass: serializa(@sub_klass) }, status: 200
    else
      render json: { errors: @sub_klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    # Pre-check: bloqueia remocao se houver personagens usando a subclasse.
    # Sem isto o `destroy` falharia com PG::ForeignKeyViolation (sheet_klasses
    # tem FK pra sub_klasses) e o front exibia mensagem cru de PG.
    in_use_count = SheetKlass.where(sub_klass_id: @sub_klass.id).count
    if in_use_count.positive?
      return render json: {
        error: "Nao e' possivel remover: #{in_use_count} personagem(ns) usam esta subclasse. " \
               'Remova ou troque a subclasse desses personagens primeiro.',
        in_use_count: in_use_count
      }, status: :unprocessable_entity
    end

    @sub_klass.destroy!
    render json: { message: 'Deletado com sucesso' }, status: 200
  rescue ActiveRecord::InvalidForeignKey => e
    # Defesa em profundidade: caso a contagem acima esteja stale por race
    # condition, devolvemos 422 (e nao 404) com mensagem amigavel.
    render json: { error: 'Nao e\' possivel remover: ainda existem referencias a esta subclasse.', detail: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def level_features
    result = Admin::LevelFeatureEditor.for_sub_klass(@sub_klass, level_feature_params)
    render json: level_feature_payload(result, :sub_klass_level), status: :created
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update_level_feature
    result = Admin::LevelFeatureEditor.for_sub_klass(
      @sub_klass,
      level_feature_params,
      feature_id: params[:feature_id],
    )
    render json: level_feature_payload(result, :sub_klass_level), status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy_level_feature
    result = Admin::LevelFeatureEditor.delete_for_sub_klass(@sub_klass, params[:feature_id], delete_level_feature_params)
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

  def set_sub_klass
    ident = params[:id].to_s
    @sub_klass = ident.match?(/\A\d+\z/) ? SubKlass.find_by(id: ident) : nil
    @sub_klass ||= SubKlass.find_by(api_index: ident)
    raise ActiveRecord::RecordNotFound, "SubKlass not found" unless @sub_klass
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  # ⚠️ `levels_json` SAIU do permit de propósito — é a manobra da fase 1, agora
  # no outro campo de regra. Enquanto esteve aqui, um PATCH com um nível apagava
  # os outros dezenove, porque `update` grava o documento inteiro. A regra entra
  # pelo `levels_patch`, que fala em níveis e é sanitizado.
  def sub_klass_params
    params.require(:sub_klass).permit(
      :name, :klass_id, :api_index, :subclass_flavor, :description, :playable,
      # Override (DM) das Magias do Círculo por Terreno — array de
      # { terrain, spells: [{ level, spellLevel, spells: [] }] }.
      # `nil` mantém o catálogo estático canônico no front.
      terrain_spells: [
        :terrain,
        { spells: [:level, :spellLevel, { spells: [] }] },
      ],
      # Magias bônus de subclasse (sempre conhecidas / sempre preparadas /
      # lista expandida). Shape espelha `SubclassData.bonusSpells/Mode`.
      bonus_spells: [
        :mode,
        { entries: [:level, :spellLevel, { spells: [] }] },
      ],
    )
  end

  # `[:ausente, []]` quando o pedido não fala de níveis — diferente de mandar um
  # patch vazio, que é "não mudei nada" e ainda assim carimba `edited_at`.
  def niveis_do_pedido(sub)
    pedido = params.require(:sub_klass)
    return [:ausente, []] unless pedido.key?(:levels_patch)

    Subclasses::LevelsPatch.aplicar(sub.linhas_de_nivel, pedido[:levels_patch])
  rescue ActionController::ParameterMissing
    [:ausente, []]
  end

  # ⚠️ Gravar a regra e projetar o que dela deriva é UM gesto. Se o sync das
  # features ou a reprojeção das magias falhar, a regra nova não pode ficar
  # gravada sozinha: era assim que `features` e `SpellSource` ficavam para trás,
  # com a página mostrando uma coisa e a ficha do jogador outra.
  def atualiza!(atributos)
    ok = false
    ActiveRecord::Base.transaction do
      @sub_klass.edited_at = Time.current if atributos.key?('levels_json')
      ok = @sub_klass.update(atributos)
      raise ActiveRecord::Rollback unless ok

      propaga_regra! if @sub_klass.saved_change_to_levels_json?
    end
    ok
  end

  # ⚠️ `update_descriptions: true` é necessário: com `false` o serviço só
  # preenche descrição VAZIA, e reescrever o texto de uma feature na página
  # nunca chegaria à ficha. É também por isso que a rake `absorve_edicoes_dm`
  # roda ANTES de a página ir ao ar — senão este sync passaria por cima do texto
  # que o mestre já tinha editado pelo compêndio.
  def propaga_regra!
    Subclasses::SyncFeaturesFromLevelsJsonService.new(@sub_klass, update_descriptions: true).call
    Subclasses::ReprojectSpellSources.call(@sub_klass)
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
