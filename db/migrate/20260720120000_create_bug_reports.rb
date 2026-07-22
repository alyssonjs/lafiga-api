class CreateBugReports < ActiveRecord::Migration[6.0]
  # Relatos de bug enviados in-app pelos usuários (botão "Relatar bug" no header).
  # Guarda conteúdo + severidade + status de triagem + contexto rico auto-capturado
  # (url/rota/personagem/sessão/navegador/usuário) e um `metadata` reservado para
  # uma futura IA de triagem escrever (resumo, duplicidade, notas). Anexos
  # (screenshots) via ActiveStorage `has_many_attached :attachments`.
  def change
    create_table :bug_reports do |t|
      t.references :user, null: false, foreign_key: true

      t.string :title, null: false
      t.text   :description, null: false
      t.text   :steps_to_reproduce

      t.integer :severity, null: false, default: 0
      t.integer :status,   null: false, default: 0

      # Contexto auto-capturado no front (jsonb opaco); metadata reservado p/ IA/DM.
      t.jsonb :context,  null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :bug_reports, [:user_id, :created_at]
    add_index :bug_reports, :status
    add_index :bug_reports, :severity
    # Opção futura (Postgres) para a IA consultar chaves do contexto:
    # add_index :bug_reports, :context, using: :gin
  end
end
