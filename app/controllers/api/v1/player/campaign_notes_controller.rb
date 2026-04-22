class Api::V1::Player::CampaignNotesController < ApplicationController
  before_action :authorize_request
  before_action :set_group,           only: [:index, :create]
  before_action :set_note,            only: [:show, :update, :destroy]

  # Lista as notas do grupo. Player só vê as visíveis a ele (group + suas
  # próprias). DM/Admin vê tudo via Admin::CampaignNotesController.
  # Aceita ?kind= e ?pinned=true para filtros leves.
  def index
    notes = @group.campaign_notes.visible_to(@current_user)
    notes = notes.where(kind: params[:kind]) if params[:kind].present?
    notes = notes.where(pinned: true) if ActiveModel::Type::Boolean.new.cast(params[:pinned])
    notes = notes.pinned_first.limit(200)
    render json: { notes: notes.map(&:as_journal_json) }, status: 200
  end

  def show
    render json: { note: @note.as_journal_json }, status: 200
  end

  def create
    note = @group.campaign_notes.new(note_params.merge(user_id: @current_user.id))
    if note.save
      render json: { note: note.as_journal_json }, status: :created
    else
      render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    # Player só pode editar a própria nota; DM/Admin tem rota específica.
    unless @note.user_id == @current_user.id
      return render json: { error: 'Você só pode editar suas próprias notas.' }, status: :forbidden
    end

    if @note.update(note_params)
      render json: { note: @note.as_journal_json }, status: 200
    else
      render json: { errors: @note.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless @note.user_id == @current_user.id
      return render json: { error: 'Você só pode remover suas próprias notas.' }, status: :forbidden
    end

    @note.destroy
    render json: { message: 'Nota removida com sucesso' }, status: 200
  end

  private

  def set_group
    @group = @current_user.groups.distinct.find_by(id: params[:group_id])
    @group ||= Group.find_by(id: params[:group_id]) # criador sem character ainda
    render(json: { error: 'Grupo não encontrado' }, status: :not_found) unless @group
  end

  def set_note
    note_id = params[:id]
    @note = CampaignNote.joins(:group)
                        .where(id: note_id)
                        .visible_to(@current_user)
                        .first
    return render(json: { error: 'Nota não encontrada' }, status: :not_found) unless @note
  end

  def note_params
    params.require(:campaign_note).permit(:title, :body, :kind, :visibility, :pinned, :schedule_id)
  end
end
