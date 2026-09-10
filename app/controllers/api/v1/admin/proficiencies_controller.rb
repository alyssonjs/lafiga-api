class Api::V1::Admin::ProficienciesController < ApplicationController
  # Gestão do catálogo de proficiências. SÓ MESTRE, como os outros compêndios.
  before_action :authorize_site_wide_dm
  before_action :set_proficiency, only: %i[show update destroy add_source remove_source]

  # GET /api/v1/admin/proficiencies?category=tool&q=ferrament
  #
  # Traz `usage_count` em cada linha: é o número que responde "quem quebra se
  # eu apagar isto". Ver `Proficiencies::UsageCounter` para por que ele não sai
  # de uma chave estrangeira.
  def index
    escopo = Proficiency.includes(:proficiency_aliases, :proficiency_sources)
    escopo = escopo.where(category: params[:category]) if params[:category].present?
    escopo = escopo.where(sub_category: params[:sub_category]) if params[:sub_category].present?
    escopo = busca(escopo, params[:q])

    uso = Proficiencies::UsageCounter.by_proficiency_id
    linhas = escopo.order(:category, :sub_category, :name).map { |p| payload(p, uso) }

    render json: {
      proficiencies: linhas,
      meta: {
        total: linhas.size,
        categories: Proficiency.group(:category).count,
        in_use: linhas.count { |l| l[:usage_count].positive? },
        trainable: linhas.count { |l| l[:trainable] },
        source_types: ProficiencySource::TYPES,
        source_type_labels: ProficiencySource::TYPE_LABELS,
      },
    }, status: :ok
  end

  def show
    render json: { proficiency: payload(@proficiency, Proficiencies::UsageCounter.by_proficiency_id) }, status: :ok
  end

  def create
    p = Proficiency.new(permitidos)
    p.api_index = derivar_api_index(p) if p.api_index.blank?
    if p.save
      aplicar_apelidos(p)
      render json: { proficiency: payload(p, {}) }, status: :created
    else
      render json: { errors: p.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # ⚠️ Renomear uma linha EM USO reescreve o que aparece na ficha de todos que
  # a citam — a resolução é por apelido, então o vínculo sobrevive, mas o texto
  # muda. Por isso a resposta devolve `usage_count`: quem chamou consegue
  # avisar depois do fato.
  def update
    if @proficiency.update(permitidos)
      aplicar_apelidos(@proficiency)
      render json: { proficiency: payload(@proficiency, Proficiencies::UsageCounter.by_proficiency_id) }, status: :ok
    else
      render json: { errors: @proficiency.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/proficiencies/:id
  #
  # ⚠️ AVISA, não bloqueia — decisão de produto (10/09/2026). Difere do
  # `admin/feats#destroy`, que recusa quando há ficha usando.
  #
  # Aqui o mestre pode apagar mesmo em uso, e o preço é real: as fichas que
  # citavam a linha ficam órfãs, e é `dnd:audit_proficiencies` que passa a
  # apontá-las. A resposta devolve o que foi apagado e quantas fichas foram
  # afetadas, para a tela conseguir dizer o que aconteceu em vez de só sumir
  # com a linha.
  def destroy
    afetadas = Proficiencies::UsageCounter.by_proficiency_id[@proficiency.id].to_i
    dados = payload(@proficiency, {})
    @proficiency.destroy
    render json: {
      deleted: dados,
      orphaned_sheets: afetadas,
      warning: afetadas.positive? ? 'sheets_orphaned' : nil,
    }.compact, status: :ok
  end

  # POST /api/v1/admin/proficiencies/:id/sources
  # body: { source: { source_type: 'race', source_key: 'anao', source_name: 'Anão' } }
  #
  # ⚠️ Entra sempre como `manual`: o `derived` é território do rake, e um
  # re-semear apagaria o que fosse marcado assim por engano.
  def add_source
    attrs = params.require(:source).permit(:source_type, :source_key, :source_name)
    src = @proficiency.proficiency_sources.new(attrs.merge(origin: 'manual'))
    if src.save
      render json: { source: { id: src.id, source_type: src.source_type, source_key: src.source_key,
                               source_name: src.source_name, origin: src.origin, label: src.label } },
             status: :created
    else
      render json: { errors: src.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/proficiencies/:id/sources/:source_id
  #
  # ⚠️ Apagar uma DERIVADA é inútil sozinho: o próximo `dnd:seed_proficiency_sources`
  # a traz de volta, porque ela reflete o que a fonte real declara. Quem quer
  # que ela suma tem de mexer no `race_rules.yml`/`class_rules.rb`. A resposta
  # diz isso em vez de deixar o mestre a achar que resolveu.
  def remove_source
    src = @proficiency.proficiency_sources.find_by(id: params[:source_id])
    return render(json: { errors: 'source not found' }, status: :not_found) unless src

    derivada = src.origin == 'derived'
    src.destroy
    render json: {
      removed: true,
      warning: derivada ? 'derived_will_return' : nil
    }.compact, status: :ok
  end

  private

  def set_proficiency
    @proficiency = Proficiency.find_by(id: params[:id]) || Proficiency.find_by(api_index: params[:id])
    render json: { errors: 'proficiency not found' }, status: :not_found unless @proficiency
  end

  # ⚠️ `aliases` fica FORA daqui de propósito: não é coluna de `Proficiency`, e
  # incluí-lo fazia o `update` estourar com `UnknownAttributeError`. Ele é lido
  # à parte, em `aplicar_apelidos`, porque vive noutra tabela.
  def permitidos
    params.require(:proficiency).permit(:api_index, :name, :category, :sub_category, :source, :published,
                                        metadata: {})
  end

  # Lista crua de grafias enviadas pelo cliente. Separada do `permitidos`
  # justamente por não ser atributo do modelo.
  def apelidos_enviados
    lista = params.dig(:proficiency, :aliases)
    lista.respond_to?(:to_a) ? Array(lista.to_a) : []
  end

  # Apelidos chegam como lista de grafias cruas; o modelo normaliza.
  #
  # ⚠️ O PRÓPRIO NOME entra sempre, e isto não é detalhe: a resolução é toda por
  # apelido, então uma linha criada sem o apelido do próprio nome seria
  # INVISÍVEL a todos os leitores — `Proficiency.resolve('Cravo')` devolveria
  # nil para uma "Cravo" que existe no catálogo. Os seeds sempre o
  # acrescentaram; a primeira versão deste controller esqueceu, e foi um teste
  # que apanhou.
  #
  # Ao RENOMEAR, o nome novo ganha apelido e o antigo FICA — é ele que mantém a
  # ficha antiga a resolver.
  #
  # ⚠️ Só ACRESCENTA. Remover apelido é o que órfã ficha antiga em silêncio, e
  # não tem porta por aqui de propósito.
  def aplicar_apelidos(prof)
    ([prof.name] + apelidos_enviados).each do |bruto|
      prof.add_alias!(bruto.to_s)
    rescue ArgumentError => e
      # Apelido já pertence a OUTRA linha — o índice único global existe para
      # isso doer. Não derruba o save, mas sai no corpo.
      (@avisos ||= []) << e.message
    end
  end

  def derivar_api_index(prof)
    prefixo = { 'language' => 'lang', 'tool' => 'tool', 'vehicle' => 'veh', 'skill' => 'skill',
                'saving_throw' => 'save', 'armor' => 'armor', 'weapon' => 'weap',
                'weapon_category' => 'wcat' }[prof.category] || 'prof'
    "#{prefixo}-#{Proficiency.normalize(prof.name).tr(' ', '-')}"
  end

  def busca(escopo, termo)
    return escopo if termo.blank?

    chave = "%#{Proficiency.normalize(termo)}%"
    escopo.left_joins(:proficiency_aliases)
          .where('LOWER(unaccent(proficiencies.name)) LIKE :k OR proficiency_aliases.alias_key LIKE :k', k: chave)
          .distinct
  rescue ActiveRecord::StatementInvalid
    # `unaccent` pode não estar instalada; cai para busca simples.
    escopo.where('LOWER(proficiencies.name) LIKE ?', "%#{termo.to_s.downcase}%")
  end

  def payload(prof, uso)
    {
      id: prof.id,
      api_index: prof.api_index,
      name: prof.name,
      category: prof.category,
      sub_category: prof.sub_category,
      metadata: prof.metadata || {},
      source: prof.source,
      published: prof.published,
      aliases: prof.proficiency_aliases.map(&:alias_key).sort,
      # Treinamento: horas necessárias, ou `nil` quando não treinável / por definir.
      trainable: prof.trainable?,
      training_hours: prof.training_hours,
      # ⚠️ Quem CONCEDE — registro, não autoridade. Marcar aqui não faz ninguém
      # ganhar a proficiência; quem concede continua a ser o `race_rules.yml` e
      # companhia. `origin` separa o derivado do que o mestre associou à mão.
      sources: prof.proficiency_sources.map { |src|
        { id: src.id, source_type: src.source_type, source_key: src.source_key,
          source_name: src.source_name, origin: src.origin, label: src.label }
      },
      usage_count: uso[prof.id].to_i,
      warnings: @avisos,
    }.compact
  end
end
