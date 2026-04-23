class Api::V1::Player::DiaryEntriesController < ApplicationController
  before_action :authorize_request
  before_action :set_character
  before_action :set_entry, only: [:show, :update, :destroy]

  # GET /api/v1/player/characters/:character_id/diary_entries
  def index
    entries = @character.diary_entries.recent_first
    render json: { diary_entries: entries.map { |e| serialize(e) } }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v1/player/characters/:character_id/diary_entries/:id
  def show
    render json: { diary_entry: serialize(@entry) }, status: :ok
  end

  # POST /api/v1/player/characters/:character_id/diary_entries
  # body: { diary_entry: { title, content, font_family, font_size, text_color, page_color, schedule_id? } }
  def create
    entry = @character.diary_entries.new(entry_params)
    if entry.save
      render json: { diary_entry: serialize(entry) }, status: :created
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/player/characters/:character_id/diary_entries/:id
  def update
    if @entry.update(entry_params)
      render json: { diary_entry: serialize(@entry) }, status: :ok
    else
      render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/player/characters/:character_id/diary_entries/:id
  def destroy
    @entry.destroy
    head :no_content
  end

  private

  def set_character
    @character = if Group.user_is_dm?(@current_user)
                   Character.find_by(id: params[:character_id])
                 else
                   @current_user.characters.find_by(id: params[:character_id])
                 end
    render json: { error: 'Character not found' }, status: :not_found if @character.nil?
  end

  def set_entry
    return unless @character
    @entry = @character.diary_entries.find_by(id: params[:id])
    render json: { error: 'Diary entry not found' }, status: :not_found unless @entry
  end

  def entry_params
    params.require(:diary_entry).permit(
      :title, :content, :font_family, :font_size,
      :text_color, :page_color, :schedule_id
    )
  end

  def serialize(entry)
    {
      id: entry.id,
      character_id: entry.character_id,
      title: entry.title,
      content: entry.content,
      font_family: entry.font_family,
      font_size: entry.font_size,
      text_color: entry.text_color,
      page_color: entry.page_color,
      schedule_id: entry.schedule_id,
      created_at: entry.created_at,
      updated_at: entry.updated_at
    }
  end
end
