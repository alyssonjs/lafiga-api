class Api::V1::Player::SchedulesController < ApplicationController
  before_action :authorize_request
  before_action :set_schedule_readable, only: [:show]
  before_action :set_schedule_mutatable, only: [:update, :destroy, :start, :complete]
  before_action :set_schedule_cancelable, only: [:cancel]
  before_action :set_schedule_map_manageable,
                only: %i[attach_battle_map detach_battle_map activate_battle_map]

  # Lista sessões (calendário hub). `dm_notes` só para DM site-wide ou dono da
  # campanha (`group.dm_user_id`). Aceita filtros:
  #   ?character_id=  → filtra pelo personagem
  #   ?group_id=      → filtra por grupo (usado pelo SessionManager)
  #   ?status=        → "completed" / lista de status
  #   ?from=YYYY-MM-DD&to=YYYY-MM-DD → range de datas (calendário mensal)
  def index
    # Hub do jogador: exibe apenas sessões dos grupos onde o usuário tem
    # personagens (character.group_id), independente do role (DM ou jogador).
    # Mutations continuam restritas em `set_schedule_mutatable` (for_hub_player).
    base = Schedule.for_player_index(@current_user)

    # Hub do personagem envia `character_id`: filtra as sessões pelo grupo
    # do personagem (`character.group_id`). Personagens sem grupo retornam
    # lista vazia — não há calendário sem grupo associado.
    if params[:character_id].present?
      character = @current_user.characters.find_by(id: params[:character_id])
      return render(json: { schedules: [] }, status: 200) unless character
      return render(json: { schedules: [] }, status: 200) unless character.group_id.present?

      base = base.where(group_id: character.group_id)
    end

    if params[:group_id].present?
      group_ids =
        if Group.user_is_dm?(@current_user)
          Group.where(id: params[:group_id]).pluck(:id)
        else
          @current_user.groups.where(id: params[:group_id]).pluck(:id)
        end
      return render(json: { schedules: [] }, status: 200) if group_ids.empty?
      base = base.where(group_id: group_ids)
    end

    if params[:status].present?
      statuses = Array(params[:status]).map(&:to_s).flat_map { |s| s.split(',') } & Schedule.statuses.keys
      base = base.where(status: statuses) if statuses.any?
    end

    if params[:from].present? || params[:to].present?
      base = base.joins(:date_dimension)
      base = base.where('date_dimensions.date >= ?', Date.parse(params[:from])) if params[:from].present?
      base = base.where('date_dimensions.date <= ?', Date.parse(params[:to])) if params[:to].present?
    end

    schedule_ids = base.distinct.pluck(:id)
    schedules = Schedule
                  .where(id: schedule_ids)
                  .includes(:date_dimension, :group, :schedule_characters)
                  .joins(:date_dimension)
                  .order('date_dimensions.date ASC')

    render json: { schedules: ScheduleSerializer.serialize_collection(schedules, viewer: @current_user) }, status: 200
  end

  def show
    render json: { schedule: serialize_schedule_for_current_user(@schedule) }, status: 200
  end

  def create
    gid = schedule_params[:group_id]
    unless Group.exists?(id: gid)
      return render json: { error: 'Grupo não encontrado' }, status: :unprocessable_entity
    end

    allowed_group =
      Group.user_is_dm?(@current_user) ||
      @current_user.groups.exists?(id: gid)
    unless allowed_group
      return render json: { error: 'Grupo inválido para este usuário' }, status: :forbidden
    end

    attrs = schedule_params.merge(status: :waiting)

    result = ScheduleService.new(attrs, current_user: @current_user).call
    if result.success?
      sched = result.result
      # Push "nova sessão marcada" p/ participantes + Mestre (fora do request).
      SessionPushJob.perform_later(sched.id, 'created', @current_user&.id)
      include_dm = schedule_dm_notes_visible_to?(@current_user, sched)
      render json: { schedule: ScheduleSerializer.serialize(sched, include_dm_notes: include_dm) }, status: :created
    else
      render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /player/schedules/sandbox — cria uma sessão-fantasma de teste (só DM).
  # Não exige grupo nem data reservável e entra direto como `in_progress`, para o
  # DM cair no /play e exercitar combate. Só o criador a vê (fora das listagens
  # de player). `group_id` opcional: se um grupo próprio for passado, a party vem
  # junto; caso contrário a sessão nasce vazia (DM adiciona NPCs/combatentes).
  def create_sandbox
    return render json: { error: 'Acesso restrito ao Mestre.' }, status: :forbidden unless Group.user_is_dm?(@current_user)

    gid = params[:group_id].presence
    if gid && !(Group.user_is_dm?(@current_user) || @current_user.groups.exists?(id: gid))
      return render json: { error: 'Grupo inválido para este usuário' }, status: :forbidden
    end

    attrs = {
      title: params[:title].presence || 'Sessão de teste',
      status: :in_progress,
      sandbox: true,
      group_id: gid,
      date: Date.current.iso8601,
    }
    result = ScheduleService.new(attrs, current_user: @current_user).call
    if result.success?
      render json: { schedule: ScheduleSerializer.serialize(result.result, include_dm_notes: true) }, status: :created
    else
      render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # GET /player/schedules/sandbox — lista as sessões de teste do próprio DM.
  def sandbox_index
    return render json: { error: 'Acesso restrito ao Mestre.' }, status: :forbidden unless Group.user_is_dm?(@current_user)

    scheds = Schedule.sandbox_of(@current_user)
                     .includes(:date_dimension)
                     .order(created_at: :desc)
    render json: { schedules: ScheduleSerializer.serialize_collection(scheds, viewer: @current_user) }, status: 200
  end

  def update
    attrs = schedule_params.to_h.deep_dup
    unless schedule_dm_notes_visible_to?(@current_user, @schedule)
      attrs.delete('dm_notes')
    end
    unless Schedule.supports_linked_npc_sheet_ids?
      attrs.delete('linked_npc_character_ids')
    end
    unless Schedule.supports_dm_temp_npc_character_ids?
      attrs.delete('dm_temp_npc_character_ids')
    end
    if attrs.key?('dm_temp_npc_character_ids') &&
       !(Group.user_is_dm?(@current_user) || @schedule.group&.owned_by?(@current_user))
      attrs.delete('dm_temp_npc_character_ids')
    end
    unless Schedule.supports_combat_groups?
      attrs.delete('combat_groups')
    end
    # Grupos de combate: só o DM da mesa / mestre da plataforma edita (espelha
    # dm_temp_npc — controle mental e atribuição de lado são DM-authoritative).
    if attrs.key?('combat_groups') &&
       !(Group.user_is_dm?(@current_user) || @schedule.group&.owned_by?(@current_user))
      attrs.delete('combat_groups')
    end

    # Metadados da mesa que precisam sincronizar em tempo real para os demais
    # clientes com a sessão aberta (só broadcast se sobreviveram às allowlists
    # acima). Ver Combat::Broadcaster.session_meta_changed.
    meta_changed = %w[combat_groups linked_npc_character_ids dm_temp_npc_character_ids]
                   .any? { |k| attrs.key?(k) }

    if attrs.key?('group_id')
      new_gid = attrs['group_id']
      if new_gid.present?
        unless Group.exists?(id: new_gid)
          return render json: { error: 'Grupo não encontrado' }, status: :unprocessable_entity
        end
        unless Group.user_is_dm?(@current_user) || @current_user.groups.exists?(id: new_gid)
          return render json: { error: 'Grupo inválido para este usuário' }, status: :forbidden
        end
      end
    end

    iso_date = attrs.delete('date')
    raw_character_ids = attrs.delete('character_ids')

    ActiveRecord::Base.transaction do
      if iso_date.present?
        d = Date.parse(iso_date.to_s)
        if d < Date.current
          return render json: { error: 'não é permitido agendar sessões em datas passadas' }, status: :unprocessable_entity
        end
        attrs['date_dimension_id'] = ScheduleService.ensure_date_dimension(iso_date)
        ScheduleService.assert_bookable_date_dimension!(attrs['date_dimension_id'])
      end

      if @schedule.update(attrs)
        if raw_character_ids
          reconcile_schedule_characters(@schedule, raw_character_ids)
        end
        fresh = @schedule.reload
        Combat::Broadcaster.session_meta_changed(fresh) if meta_changed
        render json: { schedule: serialize_schedule_for_current_user(fresh) }, status: 200
      else
        render json: { errors: @schedule.errors.full_messages }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @schedule.destroy
    render json: { message: 'Deletado com sucesso' }, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  # Marca a sessão como em andamento. Idempotente.
  def start
    @schedule.start!
    render json: { schedule: serialize_schedule_for_current_user(@schedule) }, status: 200
  rescue Schedule::StateError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Conclui a sessão e distribui XP a todos os personagens vinculados.
  # Body opcional: { xp: Integer, summary: String, highlights: [{text, type}] }
  def complete
    xp = params[:xp].presence
    summary = params[:summary].presence
    highlights = normalize_highlight_param(params[:highlights])
    @schedule.complete!(xp: xp, summary: summary, highlights: highlights)
    render json: { schedule: serialize_schedule_for_current_user(@schedule) }, status: 200
  rescue Schedule::StateError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # Cancela a sessão (sem distribuir XP). Body opcional: { reason: String }.
  def cancel
    was_cancelled = @schedule.cancelled?
    @schedule.cancel!(reason: params[:reason].presence)
    # Push "sessão cancelada" só na transição real (cancel! é idempotente).
    SessionPushJob.perform_later(@schedule.id, 'cancelled', @current_user&.id) unless was_cancelled
    render json: { schedule: serialize_schedule_for_current_user(@schedule) }, status: 200
  rescue Schedule::StateError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ===== Mapas da sessão =====
  # `battle_map_id` = mapa ATIVO (o que os jogadores veem). A junção guarda os
  # mapas VINCULADOS, que o mestre alterna durante a sessão.

  # POST /player/schedules/:id/battle_maps  { battle_map_id }
  def attach_battle_map
    map = readable_battle_map_param
    return if performed?

    MapBranch.ensure!(schedule: @schedule, map: map)

    # Primeiro mapa vinculado vira o ativo — senão a sessão ficaria com mapas
    # vinculados e nenhum aberto para a mesa.
    activate_map!(map) if @schedule.battle_map_id.blank?

    render json: { schedule: serialize_schedule_for_current_user(@schedule.reload) }, status: :ok
  end

  # DELETE /player/schedules/:id/battle_maps/:battle_map_id
  def detach_battle_map
    map_id = params[:battle_map_id].to_i
    @schedule.schedule_battle_maps.where(battle_map_id: map_id).destroy_all

    # Desvincular o mapa ATIVO deixaria a mesa olhando um mapa fora da sessão:
    # promovemos o próximo vinculado (ou nenhum) e avisamos os clientes.
    if @schedule.battle_map_id == map_id
      activate_map!(@schedule.schedule_battle_maps.ordered.first&.battle_map)
    end

    render json: { schedule: serialize_schedule_for_current_user(@schedule.reload) }, status: :ok
  end

  # POST /player/schedules/:id/activate_battle_map  { battle_map_id }
  # Troca o mapa que a mesa está vendo, em tempo real. Vincula na hora se ainda
  # não estava — o mestre escolhe da biblioteca sem precisar de dois passos.
  def activate_battle_map
    map = readable_battle_map_param
    return if performed?

    activate_map!(map)

    render json: { schedule: serialize_schedule_for_current_user(@schedule.reload) }, status: :ok
  end

  private

  # Gerenciar mapas é do mestre da mesa (ou DM site-wide) — jogador com
  # personagem na sessão NÃO troca o mapa da mesa.
  def set_schedule_map_manageable
    @schedule = Schedule.find_by(id: params[:id])
    return render(json: { error: 'Sessão não encontrada' }, status: :not_found) unless @schedule

    return if Group.user_is_dm?(@current_user) || @schedule.group&.owned_by?(@current_user)

    render json: { error: 'Apenas o mestre gerencia os mapas da sessão' }, status: :forbidden
  end

  def readable_battle_map_param
    map = BattleMap.find_by(id: params[:battle_map_id])
    unless map
      render json: { error: 'Mapa não encontrado' }, status: :not_found
      return nil
    end
    unless map.readable_by?(@current_user)
      render json: { error: 'Sem permissão para usar este mapa' }, status: :forbidden
      return nil
    end
    map
  end

  # Troca o mapa ativo e avisa a mesa em tempo real. `update_column` evita
  # disparar as validações de slot único da Schedule numa troca de mapa.
  def activate_map!(map)
    # A camada nasce AQUI, no ponto único: sem ela a leitura cairia no mapa
    # original e a mesa veria o estado de fábrica (ou o lixo de outra mesa).
    MapBranch.ensure!(schedule: @schedule, map: map)
    @schedule.update_column(:battle_map_id, map&.id)
    Combat::Broadcaster.session_meta_changed(@schedule.reload)
  end

  def set_schedule_readable
    @schedule = Schedule.find_by(id: params[:id])
    return render(json: { error: 'Sessão não encontrada' }, status: :not_found) unless @schedule
  end

  def set_schedule_mutatable
    @schedule =
      if Group.user_is_dm?(@current_user)
        Schedule.find_by(id: params[:id])
      else
        Schedule.for_hub_player(@current_user).find_by(id: params[:id])
      end
    return render(json: { error: 'Sessão não encontrada' }, status: :not_found) unless @schedule
  end

  def set_schedule_cancelable
    @schedule = Schedule.find_by(id: params[:id])
    unless @schedule
      return render(json: { error: 'Sessão não encontrada' }, status: :not_found)
    end
    unless @schedule.cancellable_by?(@current_user)
      return render(json: { error: 'Sem permissão para cancelar esta sessão' }, status: :forbidden)
    end
  end

  def schedule_dm_notes_visible_to?(user, schedule)
    ScheduleSerializer.dm_notes_visible_to_user?(user, schedule)
  end

  def serialize_schedule_for_current_user(schedule)
    ScheduleSerializer.serialize(
      schedule,
      include_dm_notes: schedule_dm_notes_visible_to?(@current_user, schedule),
    )
  end

  def schedule_params
    permitted = params.require(:schedule).permit(
      :status, :date_dimension_id, :date, :group_id, :title,
      :description, :dm_notes, :summary, :xp_awarded,
      :scheduled_time, :campaign_name,
      :started_at, :ended_at, :battle_map_id,
      highlights: [:text, :type],
      character_ids: [],
      linked_npc_character_ids: [],
      dm_temp_npc_character_ids: [],
    )

    if permitted.key?(:highlights)
      permitted[:highlights] = normalize_highlight_param(permitted[:highlights])
    end

    # `combat_groups` é um objeto jsonb aninhado (groups[] + members[] de hashes).
    # `permit` não modela array-de-hash arbitrário sem enumerar chaves; puxamos o
    # conteúdo cru (allowlist da estrutura fica no model `combat_groups_normalized`).
    raw_groups = params.dig(:schedule, :combat_groups)
    if raw_groups.present?
      permitted[:combat_groups] = raw_groups.respond_to?(:to_unsafe_h) ? raw_groups.to_unsafe_h : raw_groups
    end

    permitted
  end

  # Reconcilia o vínculo Character↔Schedule sem destruir os ScheduleCharacter
  # já existentes (preserva `status` confirmed/pending). Cria os novos ids,
  # apaga só os removidos. Valida que cada id pertence ao grupo da sessão.
  def reconcile_schedule_characters(schedule, raw_ids)
    desired = Array(raw_ids).map(&:to_i).reject(&:zero?).uniq
    group_ids = schedule.group&.characters&.pluck(:id)&.to_set || Set.new
    invalid = desired - group_ids.to_a
    raise ArgumentError, "personagens fora do grupo: #{invalid.join(',')}" if invalid.any?

    current = schedule.schedule_characters.pluck(:character_id)
    to_add = desired - current
    to_remove = current - desired

    schedule.schedule_characters.where(character_id: to_remove).destroy_all if to_remove.any?
    to_add.each do |cid|
      ScheduleCharacter.find_or_create_by!(character_id: cid, schedule_id: schedule.id)
    end
  end

  # Aceita tanto array de strings (legacy) quanto array de hashes `{text, type}`
  # vindo do form do DM. Converte para hashes simples antes de delegar para o
  # model — a validação fina e normalização do `type` ficam em Schedule.
  def normalize_highlight_param(raw)
    return nil if raw.nil?
    arr = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    return [] unless arr.is_a?(Array) || arr.is_a?(Hash)
    list = arr.is_a?(Hash) ? arr.values : arr

    list.map do |item|
      if item.is_a?(ActionController::Parameters)
        item.to_unsafe_h
      elsif item.is_a?(Hash)
        item.transform_keys(&:to_s)
      elsif item.is_a?(String)
        { 'text' => item }
      end
    end.compact
  end

end
