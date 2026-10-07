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

        # Papéis que o Mestre pode ATRIBUIR nesta tela, na ordem em que o
        # seletor os mostra. Lista branca, e não `Role.all`, porque o banco
        # ainda guarda os legados (`Admin`, `User`, `Guest`) que ninguém deve
        # voltar a distribuir — `Admin` é alias de DM e os outros dois não têm
        # significado nenhum no produto de hoje.
        ASSIGNABLE_ROLE_NAMES = %w[DM Editor Player].freeze

        # O que cada papel é, em português, para o seletor explicar a escolha
        # em vez de só mostrar a sigla.
        ROLE_DESCRIPTIONS = {
          'DM'     => 'Mestra o site todo: combate, NPCs, catálogo, utilizadores.',
          'Editor' => 'Redige a wiki e as páginas do site. Não mestra nem vê combate.',
          'Player' => 'Joga: cria personagens, entra em grupos e sessões.'
        }.freeze

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

        # GET /api/v1/admin/dm_users/roles
        # Os papéis atribuíveis, para o seletor da tela. Existe aqui, e não no
        # `RolesController`, porque aquele exige `role.name == "Admin"` — e não
        # há um único Admin em produção, então o endpoint nunca responde a
        # ninguém. Este segue o portão do resto da tela (`authorize_site_wide_dm`).
        def roles
          papeis = Role.where(name: ASSIGNABLE_ROLE_NAMES)
                       .sort_by { |r| ASSIGNABLE_ROLE_NAMES.index(r.name) }
                       .map { |r| { id: r.id, name: r.name, description: ROLE_DESCRIPTIONS[r.name] } }

          render json: { roles: papeis, meta: { total: papeis.length } }, status: :ok
        end

        def update
          papel = papel_pedido
          return if performed?

          @user.role = papel if papel

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

        # O papel pedido no PATCH, já validado. `nil` quando a chamada não
        # mexe em papel (editar nome/email continua sendo o caso comum).
        #
        # Duas recusas, e as duas importam:
        #   1. Papel fora da lista branca — ninguém volta a distribuir `Guest`
        #      nem o `Admin` legado por um PATCH à mão.
        #   2. ⚠️ Mudar o PRÓPRIO papel. O Mestre que se rebaixasse perdia o
        #      acesso a esta tela no mesmo instante e não teria por onde
        #      desfazer — e, se fosse o último, ninguém teria. Trocar de papel
        #      é sempre sobre OUTRA pessoa.
        def papel_pedido
          id = params.dig(:user, :role_id)
          return nil if id.blank?

          if @user.id == @current_user.id
            render json: { errors: ['Não dá para mudar o seu próprio papel — peça a outro Mestre.'] },
                   status: :unprocessable_entity
            return nil
          end

          papel = Role.where(name: ASSIGNABLE_ROLE_NAMES).find_by(id: id)
          return papel if papel

          render json: { errors: ["Papel inválido. Permitidos: #{ASSIGNABLE_ROLE_NAMES.join(', ')}."] },
                 status: :unprocessable_entity
          nil
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
