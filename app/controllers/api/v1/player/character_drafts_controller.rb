# Per-step character draft endpoint.
#
#   GET    /api/v1/player/character_drafts/:id?step=<key>&level=<n>
#   PATCH  /api/v1/player/character_drafts/:id
#     body: { step:, level?:, data:, expected_updated_at?, force? }
#   POST   /api/v1/player/character_drafts/:id/provision
#
# Same Character row backs both creation drafts (status: 'draft') and active
# characters being edited (status: 'active'). The mode is decided here:
#   - status: 'draft'   -> CharacterDraftSteps::*  (mutates draft_data JSONB)
#   - status: 'active'  -> CharacterSheetEdits::*  (mutates Sheet/SheetKlass live)
class Api::V1::Player::CharacterDraftsController < ApplicationController
  before_action :authorize_request
  before_action :load_character

  # GET /api/v1/player/character_drafts/:id?step=<key>&level=<n>
  def show
    step_key = params[:step].to_s
    return render(json: { error: "missing or invalid step", allowed: CharacterDraftSchema::STEP_KEYS }, status: :bad_request) unless CharacterDraftSchema::STEP_KEYS.include?(step_key)

    if creation_mode?
      svc = CharacterDraftSteps.service_for(step_key).new(character: @character, data: {}, level: params[:level])
      render json: response_envelope(step_key, svc.read, mode: 'creation', warnings: [])
    else
      svc = CharacterSheetEdits.service_for(step_key).new(character: @character, data: {}, level: params[:level], current_user: @current_user)
      render json: response_envelope(step_key, svc.read, mode: 'edit', warnings: [])
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :bad_request
  end

  # PATCH /api/v1/player/character_drafts/:id
  def update
    step_key = params[:step].to_s
    # ZC8 do segundo audit: GET respondia `{ error, allowed: [...] }`, PATCH so
    # `{ error }`. Padronizamos: em ambos verbos, step invalido devolve a lista
    # de keys aceitas — clientes podem renderizar UX util ("step desconhecido,
    # use uma destas: ...") sem ter que harcoded a lista.
    unless CharacterDraftSchema::STEP_KEYS.include?(step_key)
      return render(json: { error: 'missing or invalid step', allowed: CharacterDraftSchema::STEP_KEYS }, status: :bad_request)
    end

    if (conflict = optimistic_conflict?)
      return render(json: conflict, status: :conflict)
    end

    # ZC6 do segundo audit: antes aceitavamos `params[:data]` em qualquer formato
    # (string, array, numero) e silenciosamente cast vazia. O resultado era um
    # PATCH "no-op" que aparecia como sucesso, mascarando bugs de cliente. Agora
    # exigimos hash (ou ausencia / nil) — qualquer outro tipo retorna 400.
    raw_data = params[:data]
    payload_data =
      case raw_data
      when ActionController::Parameters then raw_data.to_unsafe_h
      when Hash                          then raw_data
      when nil                           then {}
      else
        return render(json: {
          error: 'invalid_data_shape',
          message: "campo `data` deve ser objeto/hash; recebido #{raw_data.class.name.downcase}"
        }, status: :bad_request)
      end
    level        = params[:level]
    force        = ActiveModel::Type::Boolean.new.cast(params[:force])

    if creation_mode?
      svc = CharacterDraftSteps.service_for(step_key).new(character: @character, data: payload_data, level: level, force: force)
      result = svc.call

      if result.requires_confirmation
        return render(json: { error: 'destructive_change', requires_confirmation: result.requires_confirmation }, status: :conflict)
      end

      @character.draft_data = result.draft_data
      @character.current_step = compute_current_step(step_key) if @character.respond_to?(:current_step)
      @character.save!

      log_step(:patch, step_key, mode: 'creation', warnings: result.warnings.length, cleared: result.cleared_keys.length)
      render json: response_envelope(step_key, svc.read, mode: 'creation', warnings: result.warnings, cleared: result.cleared_keys)
    else
      svc = CharacterSheetEdits.service_for(step_key).new(character: @character, data: payload_data, level: level, force: force, current_user: @current_user)
      result = svc.call

      if result.requires_confirmation
        return render(json: { error: 'destructive_change', requires_confirmation: result.requires_confirmation }, status: :conflict)
      end

      log_step(:patch, step_key, mode: 'edit', warnings: result.warnings.length, cleared: result.cleared_keys.length)
      render json: response_envelope(step_key, svc.read, mode: 'edit', warnings: result.warnings, cleared: result.cleared_keys)
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/v1/player/character_drafts/:id/provision
  #
  # Materializa um Character em status='draft' (com `draft_data` populado pelos
  # PATCH steps de criação) em uma Sheet completa. Limpa `draft_data` ao final.
  #
  # NÃO é caminho de edição. Para alterar chars já ativos:
  #   PATCH /api/v1/player/character_drafts/:id  (mode='edit')
  #
  # Camada 1 (defesa em profundidade): rejeita explicitamente uso fora do
  # contrato. Sem este guard, o `Character#save!` quebrava com mensagem
  # genérica do AR ("Validation failed: Name can't be blank") que confundia
  # diagnose porque o Sheet REAL no banco tinha esses dados; o problema é
  # que o builder só lê `draft_data`, vazio em chars active pós-provision.
  def provision
    if @character.active?
      return render json: {
        error: 'character_already_active',
        message: 'Personagem já foi provisionado. Use PATCH /character_drafts/:id ' \
                 'para editar campos individuais em modo edit.'
      }, status: :unprocessable_entity
    end

    if (@character.draft_data || {}).empty?
      return render json: {
        error: 'empty_draft',
        message: 'draft_data está vazio; nada a provisionar. Preencha steps via ' \
                 'PATCH /character_drafts/:id em modo creation antes de provisionar.'
      }, status: :unprocessable_entity
    end

    svc = CharacterProvisioningService.call(user: @current_user, character: @character, from_server_draft: true)
    if svc.success?
      raw = svc.result || {}
      char = raw[:character] || raw['character'] || @character
      reload_scope = Group.user_is_dm?(@current_user) ? Character : @current_user.characters
      char = reload_scope.preload(sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }]).find(char.id)
      render json: { character: player_character_payload(char) }, status: :created
    else
      render json: { errors: svc.errors.full_messages }, status: :unprocessable_entity
    end
  rescue CharacterDraftPayloadBuilder::IncompleteDraftError => e
    # Gap G11.1: extrai a lista de campos faltantes da mensagem para o front
    # poder exibir UX dirigida ("volte ao step Raca") sem ter que parsear
    # texto livre. Formato da msg: "draft_data incompleto: faltam X, Y — ..."
    missing = e.message[/faltam ([^—]+)/, 1]&.split(/,\s*/)&.map(&:strip)
    render json: {
      error: 'incomplete_draft',
      message: e.message,
      missing_fields: missing || []
    }, status: :unprocessable_entity
  rescue ArgumentError => e
    Rails.logger.warn("[CharacterDrafts#provision] ArgumentError: #{e.message}")
    render json: { error: 'invalid_state', message: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    # ZC4 do segundo audit: antes vazava `e.message` ao cliente. Agora retornamos
    # mensagem generica + trace_id correlacionavel ao log e classificamos como
    # 500 (erro interno), nao 422 (regra de negocio).
    trace_id = SecureRandom.hex(8)
    Rails.logger.error("[CharacterDrafts#provision] trace=#{trace_id} #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}")
    render json: {
      error: 'internal_error',
      message: 'Falha ao provisionar personagem. Tente novamente; se persistir, informe o trace_id.',
      trace_id: trace_id
    }, status: :internal_server_error
  end

  private

  def creation_mode?
    @character.draft?
  end

  def load_character
    # Phase 11 (Edit perf): preload sheet + sheet_klasses + race + sub_race +
    # background. O controller chama `effective_updated_at` em todo PATCH/GET
    # (que faz `character.sheet`, `sheet.sheet_klasses`), o services per-step
    # tipicamente acessam sheet_klasses[*].klass/sub_klass, e o response_envelope
    # serializa. Sem preload, sao 3-5 queries extras por request.
    #
    # DM/Admin (criterio canonico `Group.user_is_dm?`, mesmo de
    # `authorize_site_wide_dm`) pode editar fichas de qualquer player — caso de
    # uso real: Mestre abrindo `/character/:id/edit` de um PC importado, ou
    # corrigindo dados pos-sessao. Sem isso, todo PATCH/GET retorna 404 porque
    # `current_user.characters` filtra por `user_id = current_user.id`.
    scope = Group.user_is_dm?(@current_user) ? Character.all : @current_user.characters
    @character = scope
                  .preload(sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }])
                  .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Character not found' }, status: :not_found
  end

  # ZC2 do segundo audit: o lock otimista checava SO `Character#updated_at`,
  # mas o modo edit muta principalmente `Sheet` e `SheetKlass`. Updates a sheet
  # nao tocavam `characters.updated_at` (sem `touch: true` na associacao), entao
  # PATCHes paralelos passavam pelo guard apesar de estarem sobre dados stale.
  # Solucao: usar o MAXIMO entre Character/Sheet/SheetKlasses como token efetivo
  # de versao. O response_envelope tambem expoe esse max, garantindo que o
  # cliente sempre devolva o token mais recente do agregado.
  # Phase 10 — Bug 13: usar `try(:updated_at)` defensivo. Em DEV, ja vimos
  # cache de schema do Puma ficando stale apos migrations sem arquivo
  # (`********** NO FILE **********` em `db:migrate:status`), o que fazia
  # `Sheet#updated_at` levantar `NoMethodError` apesar da coluna existir no
  # banco. O fallback para `Time.current` garante que o controller nunca
  # responda 500 por ausencia de timestamp — pior caso o cliente recebe um
  # token "novo" e perde apenas a otimizacao de optimistic locking nessa
  # request.
  def effective_updated_at(character = @character)
    times = [character.try(:updated_at)]
    sheet = character.sheet
    if sheet
      times << sheet.try(:updated_at)
      if sheet.association(:sheet_klasses).loaded? || sheet.sheet_klasses.any?
        sheet.sheet_klasses.each { |sk| times << sk.try(:updated_at) }
      end
    end
    times.compact.max || Time.current
  end

  # Returns a Hash with conflict info if `expected_updated_at` is sent and stale.
  def optimistic_conflict?
    expected = params[:expected_updated_at]
    return nil if expected.blank?

    actual = effective_updated_at
    expected_t = begin
      Time.iso8601(expected.to_s)
    rescue ArgumentError
      return { error: 'invalid expected_updated_at' }
    end

    if (actual.to_f - expected_t.to_f).abs > 0.5 # tolerance for ms rounding
      return {
        error: 'conflict',
        expected_updated_at: expected_t.iso8601(3),
        current_updated_at: actual.iso8601(3)
      }
    end

    nil
  end

  def compute_current_step(step_key)
    idx = CharacterDraftSchema::STEP_KEYS.index(step_key)
    idx ? idx + 1 : @character.current_step
  end

  def response_envelope(step_key, data_fragment, mode:, warnings: [], cleared: [])
    # Phase 11 (Edit perf): nao chamamos `@character.reload` aqui — joga fora o
    # preload feito em `load_character` e dispara um SELECT a mais por request.
    # `effective_updated_at` ja usa `try(:updated_at)` defensivo. Em update do
    # Sheet a propria action ja fez `sheet.update!` antes de chamar isso, entao
    # o objeto em memoria tem o timestamp novo. Em GET, nao houve mutacao =>
    # nada a recarregar.
    {
      version: CharacterDraftSchema::DRAFT_SCHEMA_VERSION,
      step: step_key,
      data: data_fragment,
      current_step: @character.current_step,
      draft_data_keys: (@character.draft_data || {}).keys,
      updated_at: effective_updated_at(@character).iso8601(3),
      mode: mode,
      warnings: warnings,
      cleared_keys: cleared
    }
  end

  def log_step(action, step_key, mode:, warnings:, cleared:)
    Rails.logger.info({
      tag: 'character_draft',
      action: action,
      step: step_key,
      mode: mode,
      character_id: @character.id,
      warnings: warnings,
      cleared: cleared
    }.to_json)
  end

  # Reuses the same envelope as Api::V1::Player::CharactersController#show.
  def player_character_payload(character)
    char_data = character.as_json
    char_data[:status] = character.status
    char_data[:current_step] = character.current_step
    if character.sheet
      char_data[:sheet_id] = character.sheet.id
      char_data[:sheet] = character.sheet.as_json
      sheet_klass = character.sheet.sheet_klasses.sort_by { |sk| [-sk.level.to_i, sk.id] }.first
      char_data[:main_class] = if sheet_klass&.klass
        klass = sheet_klass.klass
        h = { id: klass.id, name: klass.name.to_s.strip.presence || klass.api_index, api_index: klass.api_index, hit_die: klass.hit_die }
        h[:subclass] = { id: sheet_klass.sub_klass.id, name: sheet_klass.sub_klass.name } if sheet_klass.sub_klass
        h
      end
    end
    char_data
  end
end
