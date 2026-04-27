# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Gestão de utilizadores pelo mestre (papel DM/Admin site-wide).
      # Criação e «resetar senha» usam sempre a palavra em texto
      # `DEFAULT_END_USER_PLAINTEXT` (literal "password" — o jogador deve alterar
      # após o primeiro acesso; não há override por variável de ambiente).
      class DmUsersController < ApplicationController
        DEFAULT_END_USER_PLAINTEXT = 'password'

        before_action :authorize_site_wide_dm
        before_action :set_user, only: %i[show update reset_password]

        MAX_PER_PAGE = 100

        def create
          pwd = DEFAULT_END_USER_PLAINTEXT
          role = default_player_role
          return unless role

          attrs = build_new_dm_user_attributes.merge(
            role: role,
            password: pwd,
            password_confirmation: pwd
          )
          @user = User.new(attrs)
          if @user.save
            render json: { user: user_payload(@user.reload, include_characters: true) }, status: :created
          else
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def index
          scope = User.includes(:role, :characters).order(
            Arel.sql('COALESCE(users.name, users.username, users.email) ASC')
          )
          if params[:q].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where(
              'LOWER(users.name) LIKE LOWER(?) OR LOWER(users.username) LIKE LOWER(?) OR LOWER(users.email) LIKE LOWER(?)',
              term, term, term
            )
          end

          page = [params.fetch(:page, 1).to_i, 1].max
          per_page = [[params.fetch(:per_page, 25).to_i, MAX_PER_PAGE].min, 1].max
          total = scope.count
          users = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            users: users.map { |u| user_list_payload(u) },
            meta: { page: page, per_page: per_page, total: total }
          }, status: :ok
        end

        def show
          render json: { user: user_payload(@user, include_characters: true) }, status: :ok
        end

        def update
          if @user.update(dm_user_params)
            render json: { user: user_payload(@user.reload, include_characters: true) }, status: :ok
          else
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # POST /api/v1/admin/dm_users/:id/reset_password
        def reset_password
          pwd = DEFAULT_END_USER_PLAINTEXT

          @user.password = pwd
          @user.password_confirmation = pwd
          if @user.save
            head :no_content
          else
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        # Bases reais: seeds usam "Player" e, às vezes, "User" (legado). Evita 500
        # se o passo de roles não corres ao nome canónico; último recurso cria "Player".
        def default_player_role
          r = Role.find_by(name: 'Player') ||
              Role.find_by(name: 'User') ||
              Role.where('LOWER(roles.name) = ?', 'player').first
          return r if r

          role = Role.create_with(
            permissions: %w[view_groups view_characters create_character join_session]
          ).find_or_create_by!(name: 'Player')
          role
        rescue StandardError => e
          Rails.logger.error("[dm_users] default_player_role: #{e.class}: #{e.message}")
          render json: {
            errors: ['Não foi possível resolver o papel de jogador. Verifique as roles (Player/User) no banco.']
          }, status: :internal_server_error
          nil
        end

        def set_user
          @user = User.includes(:role, { characters: :sheet }).find_by(id: params[:id])
          return if @user

          render json: { errors: 'User not found' }, status: :not_found
          throw :abort
        end

        def dm_user_params
          params.require(:user).permit(:name, :email)
        end

        def dm_create_params
          p = params.require(:user).permit(:name, :email, :username)
          p[:name] = p[:name].to_s.strip.presence
          p[:email] = p[:email].to_s.strip.downcase
          u = p[:username].to_s.strip
          u = u.delete_prefix('@') if u.start_with?('@')
          p[:username] = u.presence
          p
        end

        def build_new_dm_user_attributes
          h = dm_create_params.to_h.symbolize_keys
          { name: h[:name], email: h[:email], username: h[:username] }
        end

        def user_list_payload(user)
          {
            id: user.id,
            name: user.name,
            username: user.username,
            email: user.email,
            role: user.role ? { id: user.role.id, name: user.role.name } : nil,
            characters_count: user.characters.size
          }
        end

        def user_payload(user, include_characters: true)
          h = {
            id: user.id,
            name: user.name,
            username: user.username,
            email: user.email,
            role: user.role ? { id: user.role.id, name: user.role.name } : nil
          }
          if include_characters
            h[:characters] = user.characters.map { |c| character_brief(c) }
          end
          h
        end

        def character_brief(character)
          {
            id: character.id,
            name: character.name,
            status: character.status,
            current_level: character.sheet&.current_level
          }
        end
      end
    end
  end
end
