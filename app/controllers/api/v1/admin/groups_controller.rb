class Api::V1::Admin::GroupsController < ApplicationController
  # DM site-wide (papel "DM" ou "Admin") precisa dos mesmos endpoints que o
  # painel do mestre no front (`listAdminGroups`, vincular PC de qualquer
  # player). `authorize_admin_request` barrava quem nao fosse literalmente
  # "Admin", deixando a lista vazia / 401 para o mestre canonico.
  before_action :authorize_site_wide_dm
  before_action :set_group, only: [:show, :update, :destroy, :add_character, :remove_character]

  def index
    groups = Group.includes(:characters, :schedules).order(:name)
    render json: { groups: GroupSerializer.serialize_collection(groups) }, status: 200
  end

  def show
    render json: { group: GroupSerializer.serialize(@group) }, status: 200
  end

  # Diferente do player, o admin pode mover ownership entre usuarios passando
  # `dm_user_id` no payload. Quando ausente, default para o admin que esta
  # criando — assim o grupo nao fica orfao e aparece em "Meus grupos" no
  # GroupManager dele tambem.
  def create
    attrs = group_params.to_h
    attrs['dm_user_id'] = @current_user.id if attrs['dm_user_id'].blank?
    @group = Group.new(attrs)

    if @group.save
      render json: { group: GroupSerializer.serialize(@group) }, status: :created
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @group.update(group_params)
      render json: { group: GroupSerializer.serialize(@group) }, status: 200
    else
      render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @group.destroy
    render json: { message: "Deletado com sucesso" }, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  # Variantes admin de add/remove_character — DM/Admin pode vincular qualquer
  # Character (de qualquer player) a um Group. O endpoint player equivalente
  # (`Api::V1::Player::GroupsController#add_character`) restringe a characters
  # do proprio current_user, o que impedia o DM de montar a mesa quando os
  # personagens ainda nao tinham sido vinculados pelos donos.
  #
  # Body: { character_id: <id> }
  def add_character
    character = Character.find_by(id: params[:character_id])
    unless character
      return render json: { error: 'Personagem nao encontrado.' }, status: :not_found
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

  def remove_character
    character = Character.find_by(id: params[:character_id])
    unless character
      return render json: { error: 'Personagem nao encontrado.' }, status: :not_found
    end

    if character.group_id != @group.id
      return render json: { group: GroupSerializer.serialize(@group), unchanged: true }, status: 200
    end

    character.update!(group_id: nil)
    @group.reload
    render json: { group: GroupSerializer.serialize(@group) }, status: :ok
  end

  private

  def set_group
    @group = Group.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def group_params
    # Fase 4c: aceita também `cover_image` (multipart) para upload via
    # ActiveStorage. Mesmo permit do controller player + `dm_user_id`
    # (admin pode reatribuir ownership).
    params.require(:group).permit(:name, :season, :day, :year, :description, :cover_image_url, :cover_image, :dm_user_id)
  end
end
