class CreateCampaignNotes < ActiveRecord::Migration[6.0]
  # Diário compartilhado do grupo. Players e DM podem registrar notas de
  # campanha — recapitulação livre, lore, NPCs, locais. Diferente de
  # `Schedule#summary`/`highlights` (que são per-sessão), as notas vivem ao
  # longo de toda a vida do grupo e podem ser fixadas (`pinned`) para
  # alimentar a próxima sessão como "onde paramos".
  def change
    create_table :campaign_notes do |t|
      t.references :group, null: false, foreign_key: true
      t.references :schedule, null: true, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.string :title, default: "", null: false
      t.text   :body,  default: "", null: false
      t.integer :kind, default: 0, null: false
      t.integer :visibility, default: 0, null: false
      t.boolean :pinned, default: false, null: false

      t.timestamps
    end

    add_index :campaign_notes, [:group_id, :pinned]
    add_index :campaign_notes, [:group_id, :kind]
    add_index :campaign_notes, [:group_id, :updated_at]
  end
end
