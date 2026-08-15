# frozen_string_literal: true

# Web Push — lembretes de sessão.
# - push_subscriptions: assinatura de push por usuário/device (endpoint + chaves).
# - users.notify_session_reminders: opt-in do usuário (default true; só recebe se
#   também tiver assinatura ativa).
# - schedules.reminders_sent: idempotência do lembrete (marca qual tipo/data já foi
#   enviado, p/ o cron não repetir).
class CreatePushSubscriptionsAndReminderFields < ActiveRecord::Migration[6.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.text :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true

    add_column :users, :notify_session_reminders, :boolean, null: false, default: true
    add_column :schedules, :reminders_sent, :jsonb, null: false, default: {}
  end
end
