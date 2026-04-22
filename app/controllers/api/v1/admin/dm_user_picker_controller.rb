# frozen_string_literal: true

module Api
  module V1
    module Admin
      # GET /api/v1/admin/dm_user_picker
      #
      # Lista reduzida de utilizadores para o mestre (papel DM/Admin site-wide)
      # reatribuir dono de personagem. O endpoint /admin/users exige papel Admin
      # apenas; este usa `authorize_site_wide_dm` como os outros recursos DM.
      class DmUserPickerController < ApplicationController
        before_action :authorize_site_wide_dm

        MAX_LIMIT = 50

        def index
          scope = User.order(Arel.sql('COALESCE(users.name, users.username, users.email) ASC'))
          if params[:q].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where(
              'LOWER(users.name) LIKE LOWER(?) OR LOWER(users.username) LIKE LOWER(?) OR LOWER(users.email) LIKE LOWER(?)',
              term, term, term
            )
          end
          limit = [[params.fetch(:limit, 30).to_i, MAX_LIMIT].min, 1].max
          users = scope.limit(limit)

          render json: {
            users: users.map { |u| { id: u.id, name: u.name, username: u.username, email: u.email } }
          }, status: :ok
        end
      end
    end
  end
end
