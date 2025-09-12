class CreateChatModels < ActiveRecord::Migration[6.0]
  def change
    create_table :channels do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.integer :kind, null: false, default: 0 # 0: public, 1: private, 2: direct
      t.timestamps
    end
    add_index :channels, :slug, unique: true

    create_table :channel_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.timestamps
    end
    add_index :channel_memberships, [:user_id, :channel_id], unique: true, name: 'idx_channel_memberships_unique'

    create_table :messages do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.integer :kind, null: false, default: 0 # 0: user, 1: system
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :messages, :created_at
  end
end

