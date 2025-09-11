class Api::V1::Player::CharactersController < ApplicationController
  before_action :authorize_request
  before_action :get_character, only: [:show, :update, :destroy]

  def index
    scope = @current_user.characters.includes(:sheet).order(created_at: :desc)
    page = params.fetch(:page, 1).to_i
    per_page = [[params.fetch(:per_page, 25).to_i, 100].min, 1].max
    characters = scope.limit(per_page).offset((page - 1) * per_page)

    # Incluir informações da sheet e classe para cada personagem
    characters_with_sheet_info = characters.map do |char|
      char_data = char.as_json
      if char.sheet
        char_data[:sheet_id] = char.sheet.id
        char_data[:sheet] = char.sheet.as_json
        
        # Buscar classe principal
        sheet_klass = SheetKlass.where(sheet_id: char.sheet.id).first
        if sheet_klass
          klass = Klass.find_by(id: sheet_klass.klass_id)
          if klass
            char_data[:main_class] = {
              id: klass.id,
              name: klass.name,
              api_index: klass.api_index
            }
          end
          
          # Buscar subclasse se existir
          if sheet_klass.sub_klass_id
            sub_klass = SubKlass.find_by(id: sheet_klass.sub_klass_id)
            if sub_klass
              char_data[:main_class][:subclass] = {
                id: sub_klass.id,
                name: sub_klass.name
              }
            end
          end
        end
      else
        char_data[:sheet_id] = nil
        char_data[:sheet] = nil
        char_data[:main_class] = nil
      end
      char_data
    end

    render json: {
      characters: characters_with_sheet_info,
      meta: { page: page, per_page: per_page, total: scope.count }
    }, status: :ok
  end

  def show
    #only returns if the character id is from the current user (function get_character)
    char_data = @character.as_json
    
    if @character.sheet
      char_data[:sheet_id] = @character.sheet.id
      char_data[:sheet] = @character.sheet.as_json
      
      # Buscar classe principal
      sheet_klass = SheetKlass.where(sheet_id: @character.sheet.id).first
      if sheet_klass
        klass = Klass.find_by(id: sheet_klass.klass_id)
        if klass
          char_data[:main_class] = {
            id: klass.id,
            name: klass.name,
            api_index: klass.api_index
          }
        end
        
        # Buscar subclasse se existir
        if sheet_klass.sub_klass_id
          sub_klass = SubKlass.find_by(id: sheet_klass.sub_klass_id)
          if sub_klass
            char_data[:main_class][:subclass] = {
              id: sub_klass.id,
              name: sub_klass.name
            }
          end
        end
      end
    else
      char_data[:sheet_id] = nil
      char_data[:sheet] = nil
      char_data[:main_class] = nil
    end
    
    render json: { character: char_data }, status: :ok
  end

  def create
    params_with_user = character_params.merge(user_id: @current_user.id)
    character = Character.new(params_with_user)
    if character.save
      render json: { character: character }, status: :created
    else
      render json: { errors: character.errors.full_messages }, status: :unprocessable_entity
    end
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

  def character_params
    params.require(:character).permit(
      :name, :background, :group_id
    )
  end

  def get_character
    @character = @current_user.characters.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Character not found' }, status: :not_found
  end
end
