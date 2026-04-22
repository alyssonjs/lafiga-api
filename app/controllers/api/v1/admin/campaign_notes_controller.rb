class Api::V1::Admin::CampaignNotesController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_group, only: [:index, :create]
  before_action :set_note,  only: [:show, :update, :destroy]

  def index
    notes = @group.campaign_notes
    notes = notes.where(kind: params[:kind]) if params[:kind].present?
    notes = notes.pinned_first.limit(500)
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
    if @note.update(note_params)
      render json: { note: @note.as_journal_json }, status: 200
    else
      render json: { errors: @note.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @note.destroy
    render json: { message: 'Nota removida com sucesso' }, status: 200
  end

  private

  def set_group
    @group = Group.find(params[:group_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Grupo não encontrado' }, status: :not_found
  end

  def set_note
    @note = CampaignNote.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Nota não encontrada' }, status: :not_found
  end

  def note_params
    params.require(:campaign_note).permit(:title, :body, :kind, :visibility, :pinned, :schedule_id)
  end
end
