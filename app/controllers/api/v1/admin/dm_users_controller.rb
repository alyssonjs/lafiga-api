# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Gestão de utilizadores pelo mestre (papel DM/Admin site-wide).
      # Listagem, edição de nome/email, reset de senha para valor configurado em
      # ENV["DM_PASSWORD_RESET_DEFAULT"] (obrigatório em produção para usar o reset).
      class DmUsersController < ApplicationController
        before_action :authorize_site_wide_dm
        before_action :set_user, only: %i[show update reset_password]

        MAX_PER_PAGE = 100

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
          pwd = ENV['DM_PASSWORD_RESET_DEFAULT'].to_s.strip
          if pwd.blank?
            render json: {
              errors: ['DM_PASSWORD_RESET_DEFAULT não está definido no servidor. Configure a variável de ambiente.']
            }, status: :unprocessable_entity
            return
          end

          @user.password = pwd
          @user.password_confirmation = pwd
          if @user.save
            head :no_content
          else
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def set_user
          @user = User.includes(:role, { characters: :sheet }).find_by(id: params[:id])
          return if @user

          render json: { errors: 'User not found' }, status: :not_found
          throw :abort
        end

        def dm_user_params
          params.require(:user).permit(:name, :email)
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
