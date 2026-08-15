# frozen_string_literal: true

module Api
  module V1
    module Player
      # Assinaturas de Web Push do usuário (um por device). O front envia o
      # `PushSubscription.toJSON()` do browser: { endpoint, keys: { p256dh, auth } }.
      class PushSubscriptionsController < ApplicationController
        before_action :authorize_request

        # GET /api/v1/player/push_subscriptions/vapid_public_key
        def vapid_public_key
          key = Push::Sender.vapid_public_key
          return render(json: { errors: 'Web Push não configurado' }, status: 503) if key.blank?

          render json: { vapidPublicKey: key }, status: 200
        end

        # POST /api/v1/player/push_subscriptions
        def create
          endpoint = params[:endpoint].to_s
          p256dh   = params.dig(:keys, :p256dh).to_s
          auth     = params.dig(:keys, :auth).to_s
          if endpoint.blank? || p256dh.blank? || auth.blank?
            return render(json: { errors: 'Assinatura inválida' }, status: :unprocessable_entity)
          end

          # Reassocia ao usuário atual (mesmo device pode trocar de login).
          sub = PushSubscription.find_or_initialize_by(endpoint: endpoint)
          sub.assign_attributes(
            user_id: @current_user.id,
            p256dh_key: p256dh,
            auth_key: auth,
            user_agent: request.user_agent,
            last_seen_at: Time.current,
          )
          sub.save!
          head :no_content
        rescue ActiveRecord::RecordInvalid => e
          render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        # DELETE /api/v1/player/push_subscriptions  { endpoint }
        def destroy
          PushSubscription.where(user_id: @current_user.id, endpoint: params[:endpoint].to_s).destroy_all
          head :no_content
        end
      end
    end
  end
end
