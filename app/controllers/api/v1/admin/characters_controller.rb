class Api::V1::Admin::CharactersController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :get_character, only: [:show, :update, :destroy]

  # GET /api/v1/admin/characters
  #
  # Lista TODOS os personagens (PCs e NPCs) de TODOS os jogadores. Replica o
  # envelope rico do endpoint player (sheet preload + main_class + slim sheet
  # JSON) para que o front possa reusar `mapPlayerCharacterRecordToCharacter`
  # sem ramificacoes — a unica diferenca eh o bloco extra `user:` (id, name,
  # username, email) para a UI do DM identificar o dono.
  #
  # Filtros opcionais:
  #   - status:  'draft' | 'active'
  #   - user_id: integer
  #   - q:       busca case-insensitive em characters.name
  #   - page / per_page (default 25, max 100)
  def index
    scope = Character.all
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    if params[:q].present?
      scope = scope.where('LOWER(characters.name) LIKE ?', "%#{params[:q].to_s.downcase}%")
    end

    page = params.fetch(:page, 1).to_i
    per_page = [[params.fetch(:per_page, 25).to_i, 100].min, 1].max
    total = scope.count

    characters = scope
      .preload(:user, sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }])
      # updated_at: personagens recém editados aparecem na primeira página; created_at
      # empurrava PJs “antigos” para fora do corte padrão, sumindo da mesa após
      # refresh (mergedCharacters) mesmo ainda vinculados ao grupo.
      .order(updated_at: :desc)
      .limit(per_page)
      .offset((page - 1) * per_page)

    unlock_ids = CharacterDmLevelUnlock.where(character_id: characters.map(&:id)).pluck(:character_id).to_set
    payload = characters.map { |char| admin_character_payload(char, slim_sheet: true, unlock_ids: unlock_ids) }

    render json: {
      characters: payload,
      meta: { page: page, per_page: per_page, total: total }
    }, status: :ok
  end

  def show
    render json: { character: admin_character_payload(@character, slim_sheet: false) }, status: :ok
  end

  def create
    character = Character.new(character_params)
    if character.save
      render json: { character: character }, status: :created
    else
      render json: { errors: character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    raw = character_update_params
    make_npc = ActiveModel::Type::Boolean.new.cast(raw.delete(:make_npc))
    attrs = raw.to_h
    attrs[:user_id] = @current_user.id if make_npc

    ActiveRecord::Base.transaction do
      unless @character.update(attrs)
        render json: { errors: @character.errors.full_messages }, status: :unprocessable_entity
        return
      end
      promote_character_to_npc!(@character) if make_npc
      clear_npc_flag_for_player_owner!(@character) unless make_npc
    end

    @character.reload
    render json: { character: admin_character_payload(@character, slim_sheet: false) }, status: :ok
  end

  # POST /api/v1/admin/characters/provision
  # Body: { character: {... user_id? ...}, wizard: {...} }
  def provision
    payload = params.permit!.to_h
    # Admin can provision for arbitrary user via payload.character.user_id
    svc = CharacterProvisioningService.call(user: nil, actor_user: @current_user, payload: payload)
    if svc.success?
      render json: svc.result, status: :created
    else
      render json: { errors: svc.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @character.destroy
    head :no_content
  end

  private

  # Mesmo envelope que GET /player/characters (sheet, sheet_id, main_class,
  # status, current_step) + bloco user para identificar o dono na UI do DM.
  def admin_character_payload(character, slim_sheet: false, unlock_ids: nil)
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

    char_data[:user] = user_summary(character.user)
    char_data
  end

  def user_summary(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      username: user.username,
      email: user.email
    }
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
      hit_die: klass.hit_die
    }

    if sheet_klass.sub_klass
      sub_name = sheet_klass.sub_klass.name.to_s.strip.presence || sheet_klass.sub_klass.api_index.to_s.presence
      h[:subclass] = { id: sheet_klass.sub_klass.id, name: sub_name }
    end

    h
  end

  # Mesmo subset que o endpoint player — manter as duas listas em sincronia
  # garante que o mapper do front (`mapPlayerCharacterRecordToCharacter`)
  # encontre todos os campos esperados (snacks/expertise via metadata,
  # avatar_customization, etc.) sem precisar de fallback dedicado para DM.
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

  def character_params
    params.require(:character).permit(
      :name, :background, :user_id, :group_id, :status
    )
  end

  def character_update_params
    params.require(:character).permit(
      :name, :background, :user_id, :group_id, :status, :make_npc
    )
  end

  # Hub DM "Tornar NPC": dono passa a ser o mestre atual + flag em sheet.metadata['general'].
  def promote_character_to_npc!(character)
    sheet = character.sheet
    return if sheet.blank?

    sheet.with_lock do
      meta = (sheet.metadata || {}).deep_stringify_keys
      gen = (meta['general'] || {}).dup.stringify_keys
      gen['isNPC'] = true
      meta['general'] = gen
      sheet.update!(metadata: meta)
    end
  end

  # Dono jogador (papel Player) nao pode manter NPC: remove marca apos PUT (ex.: modal "Definir dono").
  def clear_npc_flag_for_player_owner!(character)
    character.reload
    user = character.user
    return if user.blank?
    return unless user.role&.name.to_s == 'Player'

    sheet = character.sheet
    return if sheet.blank?

    sheet.with_lock do
      meta = (sheet.metadata || {}).deep_stringify_keys
      gen = (meta['general'] || {}).dup.stringify_keys
      gen['isNPC'] = false
      meta['general'] = gen
      sheet.update!(metadata: meta)
    end
  end

  def dm_level_unlock_pending?(character, unlock_ids)
    if unlock_ids
      unlock_ids.include?(character.id)
    else
      CharacterDmLevelUnlock.exists?(character_id: character.id)
    end
  end

  def get_character
    @character = Character.preload(
      :user,
      sheet: [:race, :sub_race, :background, { sheet_klasses: [:klass, :sub_klass] }]
    ).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Character not found' }, status: :not_found
  end
end
