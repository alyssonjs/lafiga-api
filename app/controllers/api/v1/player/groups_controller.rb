class Api::V1::Player::GroupsController < ApplicationController
  before_action :authorize_request
  before_action :set_group, only: [:show, :update, :destroy, :timeline, :last_session, :add_character, :remove_character]

  # Jogadores: apenas grupos em que possuem ao menos um personagem.
  # Mestre (papel site-wide DM/Admin): todos os grupos — o mestre gerencia a
  # plataforma e precisa ver mesas criadas por outros DMs/admins e campanhas
  # onde ainda nao e `dm_user_id` nem tem PC proprio.
  def index
    groups =
      if Group.user_is_dm?(@current_user)
        Group.all
      else
        group_ids = Character.where(user_id: @current_user.id).where.not(group_id: nil).distinct.pluck(:group_id)
        owned_ids = @current_user.owned_groups.distinct.pluck(:id)
        Group.where(id: (group_ids + owned_ids).uniq)
      end

    groups = groups
      .includes(:schedules, characters: { sheet: [:race, { sheet_klasses: %i[klass sub_klass] }] })
      .order(:name)

    render json: { groups: GroupSerializer.serialize_collection(groups) }, status: 200
  end

  def show
    render json: { group: GroupSerializer.serialize(@group) }, status: 200
  end

  # Apenas mestre (papel site-wide DM ou Admin) pode criar grupos pela rota
  # player. Jogadores entram em campanhas quando o mestre vincula o personagem
  # (ou via fluxo admin). `dm_user_id = current_user.id` é setado pelo servidor.
  def create
    unless Group.user_is_dm?(@current_user)
      return render json: { error: 'Apenas o mestre pode criar, editar ou remover grupos.' }, status: :forbidden
    end

    group = Group.new(group_params.merge(dm_user_id: @current_user.id))
    if group.save
      render json: { group: GroupSerializer.serialize(group) }, status: :created
    else
      render json: { errors: group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    unless Group.user_is_dm?(@current_user)
      return render json: { error: 'Apenas o mestre pode criar, editar ou remover grupos.' }, status: :forbidden
    end

    if @group.update(group_params)
      render json: { group: GroupSerializer.serialize(@group) }, status: 200
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless Group.user_is_dm?(@current_user)
      return render json: { error: 'Apenas o mestre pode criar, editar ou remover grupos.' }, status: :forbidden
    end

    @group.destroy
    render json: { message: 'Grupo removido com sucesso' }, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Linha do tempo da campanha — todas as sessões do grupo ordenadas
  # cronologicamente, acompanhadas das notas de campanha. Alimenta a aba
  # "Diário" e o card "Onde paramos" no SessionManager.
  def timeline
    schedules = @group.schedules
                      .includes(:date_dimension, :schedule_characters)
                      .chronological
                      .to_a

    notes = @group.campaign_notes.visible_to(@current_user).pinned_first.limit(50)

    last = @group.schedules.concluded.chronological.last
    render json: {
      group: GroupSerializer.serialize(@group),
      schedules: ScheduleSerializer.serialize_collection(schedules, viewer: @current_user),
      notes: notes.map(&:as_journal_json),
      last_completed: last && ScheduleSerializer.serialize(
        last,
        include_dm_notes: ScheduleSerializer.dm_notes_visible_to_user?(@current_user, last),
      ),
    }, status: 200
  end

  # Vincula um Character (do próprio usuário) ao grupo. Valida ownership por
  # segurança — um player nunca pode mexer no group_id do personagem alheio.
  # Body: { character_id: 123 }
  def add_character
    character = @current_user.characters.find_by(id: params[:character_id])
    unless character
      return render json: { error: 'Personagem não encontrado ou não pertence a você.' }, status: :forbidden
    end

    if character.group_id == @group.id
      return render json: { group: GroupSerializer.serialize(@group), unchanged: true }, status: 200
    end

    character.update!(group_id: @group.id)
    @group.reload
    render json: { group: GroupSerializer.serialize(@group) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # Desvincula um Character do grupo. Player só pode desvincular characters
  # próprios; o DM (Admin) tem rota separada caso precise mexer em alheio.
  def remove_character
    character = @current_user.characters.find_by(id: params[:character_id])
    unless character
      return render json: { error: 'Personagem não encontrado ou não pertence a você.' }, status: :forbidden
    end

    if character.group_id != @group.id
      return render json: { group: GroupSerializer.serialize(@group), unchanged: true }, status: 200
    end

    character.update!(group_id: nil)
    @group.reload
    render json: { group: GroupSerializer.serialize(@group) }, status: :ok
  end

  # "Onde paramos" — usado quando o player vai abrir uma nova sessão. Devolve
  # o último recap concluído (ou em andamento) e as notas pinned, em payload
  # enxuto para popular o modal de criação.
  def last_session
    last = @group.schedules.where(status: [:completed, :in_progress]).chronological.last

    render json: {
      last_session: last&.recap_payload,
      pinned_notes: @group.campaign_notes
                          .visible_to(@current_user)
                          .where(pinned: true)
                          .recent_first
                          .limit(20)
                          .map(&:as_journal_json),
    }, status: 200
  end

  private

  # Localiza o grupo e valida autorização de leitura / ações de membro.
  #
  # - Mestre site-wide (DM/Admin): acesso a qualquer grupo (painel do mestre).
  # - Jogador: somente se possuir ao menos um personagem naquele grupo.
  #   Não basta ser `dm_user_id` legado sem PC — evita campanha "fantasma"
  #   visível só por ter sido criador sem personagem vinculado.
  def set_group
    @group = Group
      .includes(characters: { sheet: [:race, { sheet_klasses: %i[klass sub_klass] }] })
      .find_by(id: params[:id])
    return render(json: { error: 'Grupo não encontrado' }, status: :not_found) unless @group

    authorized = if Group.user_is_dm?(@current_user)
                   true
                 else
                   @group.characters.exists?(user_id: @current_user.id)
                 end
    return render(json: { error: 'Grupo não encontrado' }, status: :not_found) unless authorized
  end

  def group_params
    # Fase 4c: aceita também `cover_image` (multipart/form-data) para upload
    # via ActiveStorage. Quando enviado, o serializer responde com a URL
    # gerada pelo blob (substituindo eventual `cover_image_url` legado).
    params.require(:group).permit(:name, :season, :day, :year, :description, :cover_image_url, :cover_image)
  end
end
