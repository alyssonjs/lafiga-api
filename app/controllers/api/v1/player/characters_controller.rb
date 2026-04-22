class Api::V1::Player::CharactersController < ApplicationController
  before_action :authorize_request
  before_action :get_character, only: [:show, :update, :destroy]

  def index
    base = @current_user.characters
    base = base.where(status: params[:status]) if params[:status].present?
    page = params.fetch(:page, 1).to_i
    per_page = [[params.fetch(:per_page, 25).to_i, 100].min, 1].max
    total = base.count
    characters = base.preload(sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }])
      .order(created_at: :desc)
      .limit(per_page)
      .offset((page - 1) * per_page)

    unlock_ids = CharacterDmLevelUnlock.where(character_id: characters.map(&:id)).pluck(:character_id).to_set
    characters_with_sheet_info = characters.map { |char| player_character_payload(char, slim_sheet: true, unlock_ids: unlock_ids) }

    render json: {
      characters: characters_with_sheet_info,
      meta: { page: page, per_page: per_page, total: total }
    }, status: :ok
  end

  def show
    #only returns if the character id is from the current user (function get_character)
    char_data = @character.as_json
    char_data[:status] = @character.status
    char_data[:current_step] = @character.current_step
    
    if @character.sheet
      char_data[:sheet_id] = @character.sheet.id
      char_data[:sheet] = sheet_json_for_list(@character.sheet)
      char_data[:main_class] = main_class_json_for_sheet(@character.sheet)
    else
      char_data[:sheet_id] = nil
      char_data[:sheet] = nil
      char_data[:main_class] = nil
    end
    
    render json: { character: char_data }, status: :ok
  end

  def create
    params_with_user = character_params.merge(user_id: @current_user.id)
    # ZC5 do segundo audit: status nao e mais aceito do cliente. Toda criacao via
    # POST /characters comeca como `draft` — ativacao acontece via wizard/provision
    # ou via update administrativo, nao por flag livre no payload.
    params_with_user[:status] = 'draft'
    character = Character.new(params_with_user)
    if character.save
      render json: { character: character }, status: :created
    else
      render json: { errors: character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/player/characters/provision
  # Body: { character: {...}, wizard: {...} }
  #
  # ZC1 do segundo audit: a versao antiga usava `params.permit!.to_h`, que
  # whitelist tudo (incluindo chaves arbitrarias injetaveis pelo cliente). Como
  # `CharacterProvisioningService` so consome `character` e `wizard`, restringimos
  # explicitamente o payload a essas duas chaves. `to_unsafe_h` interno preserva
  # a estrutura aninhada arbitraria de `draft_data` / `wizard` (que e jsonb livre).
  def provision
    raw = params.permit(character: {}, wizard: {})
    payload = {
      'character' => (params[:character].respond_to?(:to_unsafe_h) ? params[:character].to_unsafe_h : (raw[:character] || {}).to_h),
      'wizard'    => (params[:wizard].respond_to?(:to_unsafe_h)    ? params[:wizard].to_unsafe_h    : (raw[:wizard] || {}).to_h),
    }
    svc = CharacterProvisioningService.call(user: @current_user, payload: payload)
    if svc.success?
      raw = svc.result || {}
      char = raw[:character] || raw['character']
      # DM/Admin pode reprovisionar fichas alheias — recarregar via escopo
      # global preservando o player owner real do char.
      reload_scope = Group.user_is_dm?(@current_user) ? Character : @current_user.characters
      char = reload_scope.preload(sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }]).find(char.id)
      render json: { character: player_character_payload(char) }, status: :created
    else
      render json: { errors: svc.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    # ZC4 do segundo audit: antes vazava `e.message` cru — informacao de
    # implementacao interna (nomes de classes, queries SQL parciais em erros do
    # Postgres, etc.) era enviada ao cliente. Agora logamos a excecao completa
    # e retornamos uma mensagem generica + um trace id correlacionavel.
    trace_id = SecureRandom.hex(8)
    Rails.logger.error("[characters#provision] trace=#{trace_id} #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}")
    render json: {
      error: 'internal_error',
      message: 'Falha ao provisionar personagem. Tente novamente; se persistir, informe o trace_id.',
      trace_id: trace_id
    }, status: :internal_server_error
  end

  def update
    #only updates if the character id is from the current user (function get_character)
    if @character.update(character_params)
      render json: { character: @character }, status: :ok
    else
      render json: { errors: @character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @character.destroy
    head :no_content
  end

  private

  # Mesmo envelope que GET show — o front usa main_class.name na ficha; as_json do Character não inclui isso.
  def player_character_payload(character, slim_sheet: false, unlock_ids: nil)
    char_data = character.as_json
    char_data[:status] = character.status
    char_data[:current_step] = character.current_step
    char_data[:pending_dm_level_up] = dm_level_unlock_pending?(character, unlock_ids)
    if character.sheet
      char_data[:sheet_id] = character.sheet.id
      char_data[:sheet] = sheet_json_for_list(character.sheet, slim: slim_sheet)
      char_data[:main_class] = main_class_json_for_sheet(character.sheet)
    else
      char_data[:sheet_id] = nil
      char_data[:sheet] = nil
      char_data[:main_class] = nil
    end
    char_data
  end

  def main_class_json_for_sheet(sheet)
    return nil unless sheet&.id

    sheet_klass = sheet.sheet_klasses.sort_by { |sk| [-sk.level.to_i, sk.id] }.first
    return nil unless sheet_klass

    klass = sheet_klass.klass
    return nil unless klass

    display_name = klass.name.to_s.strip.presence || klass.api_index.to_s.presence
    h = {
      id: klass.id,
      name: display_name,
      api_index: klass.api_index,
      hit_die: klass.hit_die,
      sheet_klass_id: sheet_klass.id
    }

    if sheet_klass.sub_klass
      sub_name = sheet_klass.sub_klass.name.to_s.strip.presence || sheet_klass.sub_klass.api_index.to_s.presence
      h[:subclass] = { id: sheet_klass.sub_klass.id, name: sub_name }
    end

    h
  end

  # Sheet JSON for list/show: include association names so the frontend card does not depend on race_summary JSONB alone.
  # Inclui `metadata` para que o front-end (mapPlayerCharacterRecordToCharacter)
  # tenha acesso a `class_choices.per_level` (snacks, expertise, skills) ao construir
  # `Character.sheetMetadata` — sem isso, Cozinheiro mostra "Petiscos Conhecidos = 0"
  # e expertise some no merge da ficha completa.
  SHEET_LIST_COLUMNS = %w[
    id character_id current_level
    str dex con int wis cha
    hp_max hp_current temp_hp
    race_id sub_race_id alignment_id background_id background_key
    avatar_customization
    metadata
    coins
    experience_points
  ].freeze

  def sheet_json_for_list(sheet, slim: false)
    h = slim ? sheet.as_json(only: SHEET_LIST_COLUMNS) : sheet.as_json
    begin
      h[:race] = { id: sheet.race.id, name: sheet.race.name } if sheet.race
      h[:sub_race] = { id: sheet.sub_race.id, name: sheet.sub_race.name } if sheet.sub_race
      h[:background_record] = { id: sheet.background.id, name: sheet.background.name } if sheet.background
    rescue StandardError
    end
    h
  end

  # ZC5 do segundo audit: a versao antiga aceitava `:status` e `:current_step`
  # vindos do cliente — atalho para fora do wizard, podia "concluir" um draft
  # sem passar pelos guards de validacao. Agora removemos as duas chaves do
  # whitelist; quem precisa muda-las e o action `update` (admin-only) ou
  # CharacterDraftSchema/services oficiais (que recalculam a partir do step).
  def character_params
    permitted = params.require(:character).permit(
      :name,
      :background,
      :group_id
    )
    # draft_data is a jsonb column storing arbitrary nested wizard state —
    # pass it through without strong-parameter filtering.
    raw_dd = params[:character][:draft_data]
    if raw_dd.present?
      permitted[:draft_data] = raw_dd.is_a?(ActionController::Parameters) ? raw_dd.to_unsafe_h : raw_dd
    end
    permitted
  end

  def dm_level_unlock_pending?(character, unlock_ids)
    if unlock_ids
      unlock_ids.include?(character.id)
    else
      CharacterDmLevelUnlock.exists?(character_id: character.id)
    end
  end

  def get_character
    # DM/Admin pode visualizar/editar fichas de qualquer player — mesmo padrao
    # de Group.user_is_dm? usado em sheets/character_drafts.
    scope = Group.user_is_dm?(@current_user) ? Character.all : @current_user.characters
    @character = scope.preload(sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }]).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Character not found' }, status: :not_found
  end
end
